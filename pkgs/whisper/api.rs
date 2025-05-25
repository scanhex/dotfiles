use crate::config::Config;
use anyhow::{anyhow, Context, Result};
use base64::{engine::general_purpose::STANDARD as BASE64_STANDARD, Engine as _};
use log::{debug, info, warn};
use reqwest::{multipart, Body, Client, StatusCode};
use serde::{Deserialize, Serialize};
use serde_json::Value; // For handling flexible JSON structures
use std::path::Path;
use std::time::Duration;
use tokio::fs::File;
use tokio::time::sleep;
use tokio_util::codec::{BytesCodec, FramedRead};

// Replicate constants
const REPLICATE_API_URL: &str = "https://api.replicate.com/v1/predictions";
const REPLICATE_MODEL_VERSION: &str =
    "3ab86df6c8f54c11309d4d1f930ac292bad43ace52d10c80d87eb258b3c9f79c"; // Whisper v3 large turbo
const REPLICATE_POLL_INTERVAL: Duration = Duration::from_secs(1);
const REPLICATE_POLL_TIMEOUT: Duration = Duration::from_secs(120);

// ElevenLabs constants
const ELEVENLABS_API_URL: &str = "https://api.elevenlabs.io/v1/speech-to-text";
const ELEVENLABS_MODEL: &str = "scribe_v1"; // Or allow configuration

// OpenAI constants
const OPENAI_API_URL: &str = "https://api.openai.com/v1/audio/transcriptions";
const OPENAI_MODEL: &str = "gpt-4o-transcribe"; 

// --- Replicate ---

#[derive(Serialize)]
struct ReplicateInput {
    audio: String, // data URI
    // Add other whisper params if needed (e.g., language, prompt)
    batch_size: u32, // As used in Python example
}

#[derive(Serialize)]
struct ReplicateCreatePayload<'a> {
    version: &'a str,
    input: ReplicateInput,
}

#[derive(Deserialize, Debug)]
struct ReplicateCreateResponse {
    id: String,
    urls: ReplicateUrls,
}

#[derive(Deserialize, Debug)]
struct ReplicateUrls {
    get: String,
    // cancel: String,
}

#[derive(Deserialize, Debug)]
struct ReplicatePollResponse {
    status: String,        // "starting", "processing", "succeeded", "failed", "canceled"
    output: Option<Value>, // Flexible output structure
    error: Option<String>,
}

pub async fn transcribe_replicate(config: &Config, audio_path: &Path) -> Result<String> {
    let client = Client::new();
    let api_token = &config.api_key;

    // 1. Read audio and convert to data URI
    let audio_bytes = tokio::fs::read(audio_path)
        .await
        .context("Failed to read audio file")?;
    let audio_base64 = BASE64_STANDARD.encode(&audio_bytes);
    // Assuming WAV format from input
    let audio_data_uri = format!("data:audio/wav;base64,{}", audio_base64);
    debug!(
        "Audio size: {} bytes, Data URI prefix: data:audio/wav;base64,...",
        audio_bytes.len()
    );

    // 2. Create Prediction
    let create_payload = ReplicateCreatePayload {
        version: REPLICATE_MODEL_VERSION,
        input: ReplicateInput {
            audio: audio_data_uri,
            batch_size: 64,
        },
    };

    let mut prediction_url: Option<String> = None;
    for attempt in 0..=config.retries {
        if attempt > 0 {
            let delay = Duration::from_secs(2u64.pow(attempt - 1));
            info!(
                "Retrying Replicate create prediction (attempt {}) after {:?}",
                attempt + 1,
                delay
            );
            sleep(delay).await;
        }

        let response = client
            .post(REPLICATE_API_URL)
            .bearer_auth(api_token)
            .json(&create_payload)
            .timeout(Duration::from_secs(30))
            .send()
            .await;

        match response {
            Ok(resp) => {
                let status = resp.status();
                debug!("Replicate Create Status: {}", status);
                if status.is_success() {
                    let create_resp = resp.json::<ReplicateCreateResponse>().await?;
                    prediction_url = Some(create_resp.urls.get);
                    info!(
                        "Replicate prediction created: ID={}, URL={}",
                        create_resp.id,
                        prediction_url.as_ref().unwrap()
                    );
                    break;
                } else if status == StatusCode::TOO_MANY_REQUESTS || status.is_server_error() {
                    warn!("Replicate create failed ({}), retrying...", status);
                    continue;
                } else {
                    let error_text = resp
                        .text()
                        .await
                        .unwrap_or_else(|_| "Failed to read error body".into());
                    return Err(anyhow!(
                        "Replicate create failed ({}): {}",
                        status,
                        error_text
                    ));
                }
            }
            Err(e) => {
                if e.is_timeout() && attempt < config.retries {
                    warn!("Replicate create timed out, retrying...");
                    continue;
                } else if e.is_connect() && attempt < config.retries {
                    warn!("Replicate create connection error, retrying...");
                    continue;
                }
                return Err(anyhow!("Replicate create request failed: {}", e).context(e));
            }
        }
    } // End create retry loop

    let get_url = prediction_url.context("Failed to create Replicate prediction after retries.")?;

    // 3. Poll for Result
    let start_time = tokio::time::Instant::now();
    loop {
        if start_time.elapsed() > REPLICATE_POLL_TIMEOUT {
            return Err(anyhow!(
                "Replicate polling timed out after {:?}",
                REPLICATE_POLL_TIMEOUT
            ));
        }

        info!(
            "Polling Replicate status ({:?} elapsed)...",
            start_time.elapsed()
        );
        let poll_response = client
            .get(&get_url)
            .bearer_auth(api_token)
            .timeout(Duration::from_secs(15))
            .send()
            .await;

        match poll_response {
            Ok(resp) => {
                let status = resp.status();
                debug!("Replicate Poll Status: {}", status);
                if status.is_success() {
                    let prediction = resp.json::<ReplicatePollResponse>().await?;
                    match prediction.status.as_str() {
                        "succeeded" => {
                            info!("Replicate prediction succeeded.");
                            // Extract transcription text (handle various possible output formats)
                            return extract_replicate_transcription(prediction.output);
                        }
                        "failed" => {
                            return Err(anyhow!(
                                "Replicate prediction failed: {}",
                                prediction.error.unwrap_or_else(|| "Unknown error".into())
                            ));
                        }
                        "canceled" => {
                            return Err(anyhow!("Replicate prediction canceled."));
                        }
                        "starting" | "processing" => {
                            // Continue polling
                        }
                        unknown => {
                            warn!("Unknown Replicate status: {}", unknown);
                        }
                    }
                } else if status == StatusCode::TOO_MANY_REQUESTS || status.is_server_error() {
                    warn!("Replicate poll received status {}, waiting...", status);
                    sleep(REPLICATE_POLL_INTERVAL * 2).await; // Wait longer
                    continue;
                } else {
                    let error_text = resp
                        .text()
                        .await
                        .unwrap_or_else(|_| "Failed to read error body".into());
                    return Err(anyhow!(
                        "Replicate poll failed ({}): {}",
                        status,
                        error_text
                    ));
                }
            }
            Err(e) => {
                if e.is_timeout() {
                    warn!("Replicate poll timed out, continuing poll...");
                } else {
                    warn!("Replicate poll request error: {}, continuing poll...", e);
                    sleep(REPLICATE_POLL_INTERVAL * 2).await; // Wait longer after error
                }
            }
        } // End match poll_response

        sleep(REPLICATE_POLL_INTERVAL).await;
    } // End poll loop
}

fn extract_replicate_transcription(output: Option<Value>) -> Result<String> {
    match output {
        Some(Value::Object(map)) => {
            // Look for common keys
            if let Some(text) = map.get("transcription").and_then(|v| v.as_str()) {
                Ok(text.trim().to_string())
            } else if let Some(text) = map.get("text").and_then(|v| v.as_str()) {
                Ok(text.trim().to_string())
            } else if let Some(Value::Array(segments)) = map.get("segments") {
                // Assemble from segments
                let combined = segments
                    .iter()
                    .filter_map(|seg| seg.get("text").and_then(|t| t.as_str()))
                    .map(|s| s.trim())
                    .collect::<Vec<&str>>()
                    .join(" ");
                Ok(combined.trim().to_string())
            } else {
                Err(anyhow!("Could not find 'transcription', 'text', or 'segments' in Replicate output object: {:?}", map))
            }
        }
        Some(Value::String(s)) => {
            // Sometimes the output is just the string
            Ok(s.trim().to_string())
        }
        _ => Err(anyhow!(
            "Unexpected or missing output format from Replicate: {:?}",
            output
        )),
    }
}

// --- ElevenLabs ---

#[derive(Deserialize, Debug)]
struct ElevenLabsResponse {
    text: String,
}

pub async fn transcribe_elevenlabs(config: &Config, audio_path: &Path) -> Result<String> {
    let client = Client::new();
    let api_key = &config.api_key;

    // Prepare multipart form data

    for attempt in 0..=config.retries {
        if attempt > 0 {
            let delay = Duration::from_secs(2u64.pow(attempt - 1));
            info!(
                "Retrying ElevenLabs API call (attempt {}) after {:?}",
                attempt + 1,
                delay
            );
            sleep(delay).await;
        }
        let file = File::open(audio_path)
            .await
            .context("Failed to open audio file for ElevenLabs upload")?;
        let stream = FramedRead::new(file, BytesCodec::new());
        let file_body = Body::wrap_stream(stream);

        let audio_part = multipart::Part::stream(file_body)
            .file_name(
                audio_path
                    .file_name()
                    .map_or("audio.wav".into(), |n| n.to_string_lossy().into_owned()),
            )
            .mime_str("audio/wav")?;

        let form = multipart::Form::new()
            .text("model_id", ELEVENLABS_MODEL.to_string())
            .part("file", audio_part);

        let response = client
            .post(ELEVENLABS_API_URL)
            .header("xi-api-key", api_key)
            .multipart(form) // Send the potentially rebuilt/cloned form
            .timeout(Duration::from_secs(45)) // Longer timeout for upload/processing
            .send()
            .await;

        match response {
            Ok(resp) => {
                let status = resp.status();
                debug!("ElevenLabs API Status Code: {}", status);
                if status.is_success() {
                    let result = resp.json::<ElevenLabsResponse>().await?;
                    return Ok(result.text.trim().to_string());
                } else if status == StatusCode::TOO_MANY_REQUESTS || status.is_server_error() {
                    warn!("ElevenLabs API failed ({}), retrying...", status);
                    // No need to reset file pointer manually, form rebuilt on retry
                    continue;
                } else {
                    let error_text = resp
                        .text()
                        .await
                        .unwrap_or_else(|_| "Failed to read error body".into());
                    return Err(anyhow!(
                        "ElevenLabs API call failed ({}): {}",
                        status,
                        error_text
                    ));
                }
            }
            Err(e) => {
                if e.is_timeout() && attempt < config.retries {
                    warn!("ElevenLabs request timed out, retrying...");
                    // Rebuild form on next iteration
                    continue;
                } else if e.is_connect() && attempt < config.retries {
                    warn!("ElevenLabs connection error, retrying...");
                    // Rebuild form on next iteration
                    continue;
                }
                return Err(anyhow!("ElevenLabs API request failed: {}", e).context(e));
            }
        }
    } // End retry loop

    Err(anyhow!(
        "ElevenLabs API call failed after {} retries.",
        config.retries
    ))
}

// --- OpenAI ---

#[derive(Deserialize, Debug)]
struct OpenAIResponse {
    text: String,
}

pub async fn transcribe_openai(config: &Config, audio_path: &Path) -> Result<String> {
    let client = Client::new();
    let api_key = &config.api_key;

    if api_key.is_empty() {
        return Err(anyhow!(
            "OpenAI API key is missing. Please provide it via --api-key or OPENAI_API_KEY env var."
        ));
    }

    for attempt in 0..=config.retries {
        if attempt > 0 {
            let delay = Duration::from_secs(2u64.pow(attempt - 1));
            info!(
                "Retrying OpenAI API call (attempt {}) after {:?}" ,
                attempt + 1,
                delay
            );
            sleep(delay).await;
        }

        // Re-open file and prepare form data inside the loop for retries
        let file = File::open(audio_path)
            .await
            .context("Failed to open audio file for OpenAI upload")?;
        let stream = FramedRead::new(file, BytesCodec::new());
        let file_body = Body::wrap_stream(stream);

        let audio_part = multipart::Part::stream(file_body)
            .file_name(
                audio_path
                    .file_name()
                    .map_or("audio.wav".into(), |n| n.to_string_lossy().into_owned()),
            )
            .mime_str("audio/wav")?; // OpenAI supports various formats, wav is safe

        let form = multipart::Form::new()
            .text("model", OPENAI_MODEL.to_string())
            .text("prompt", "The following recording is made by a technical user who knows computer science and software engineering well.")
            .part("file", audio_part);

        let response = client
            .post(OPENAI_API_URL)
            .bearer_auth(api_key)
            .multipart(form)
            .timeout(Duration::from_secs(60)) // Increased timeout for potential processing
            .send()
            .await;

        match response {
            Ok(resp) => {
                let status = resp.status();
                debug!("OpenAI API Status Code: {}", status);
                if status.is_success() {
                    let result = resp.json::<OpenAIResponse>().await.context("Failed to parse OpenAI JSON response")?;
                    info!("OpenAI transcription successful.");
                    return Ok(result.text.trim().to_string());
                } else if status == StatusCode::TOO_MANY_REQUESTS || status.is_server_error() {
                    warn!("OpenAI API failed ({}), retrying...", status);
                    continue; // Retry
                } else {
                    let error_text = resp
                        .text()
                        .await
                        .unwrap_or_else(|_| "Failed to read error body".into());
                    return Err(anyhow!(
                        "OpenAI API call failed ({}): {}",
                        status,
                        error_text
                    ));
                }
            }
            Err(e) => {
                // Retry on timeout or connection errors
                if (e.is_timeout() || e.is_connect()) && attempt < config.retries {
                    warn!("OpenAI request error ({}), retrying...", e);
                    continue; // Retry
                } else {
                    // For other errors or if retries exhausted, return the error
                    return Err(anyhow!("OpenAI API request failed: {}", e).context(e));
                }
            }
        }
    } // End retry loop

    Err(anyhow!(
        "OpenAI API call failed after {} retries.",
        config.retries
    ))
}
