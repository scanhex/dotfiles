use crate::config::Config;
use anyhow::{anyhow, Context, Result};
use base64::{engine::general_purpose::STANDARD as BASE64_STANDARD, Engine as _};
use futures_util::{SinkExt, StreamExt};
use log::{debug, info, warn};
use reqwest::{multipart, Body, Client, StatusCode};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value}; // For handling flexible JSON structures
use std::io::{self, Write};
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;
use tokio::fs::File;
use tokio::sync::mpsc;
use tokio::time::sleep;
use tokio_tungstenite::connect_async;
use tokio_tungstenite::tungstenite::{client::IntoClientRequest, Message};
use tokio_util::codec::{BytesCodec, FramedRead};

// Replicate constants
const REPLICATE_API_URL: &str = "https://api.replicate.com/v1/predictions";
const REPLICATE_MODEL_VERSION: &str =
    "3ab86df6c8f54c11309d4d1f930ac292bad43ace52d10c80d87eb258b3c9f79c"; // Whisper v3 large turbo
const REPLICATE_POLL_INTERVAL: Duration = Duration::from_secs(1);
const REPLICATE_POLL_TIMEOUT: Duration = Duration::from_secs(120);

// ElevenLabs constants
const ELEVENLABS_API_URL: &str = "https://api.elevenlabs.io/v1/speech-to-text";
const ELEVENLABS_MODEL: &str = "scribe_v2";

// OpenAI constants
const OPENAI_API_URL: &str = "https://api.openai.com/v1/audio/transcriptions";
const OPENAI_MODEL: &str = "gpt-4o-transcribe";
const OPENAI_REALTIME_WS_URL: &str = "wss://api.openai.com/v1/realtime?intent=transcription";
const OPENAI_REALTIME_TRANSCRIPTION_MODEL: &str = "gpt-realtime-whisper";
const OPENAI_REALTIME_SAMPLE_RATE: u32 = 24_000;
const OPENAI_REALTIME_COMMIT_INTERVAL: Duration = Duration::from_millis(1_500);
// 100ms — OpenAI rejects commits with less audio than this as a fatal error event.
const OPENAI_REALTIME_MIN_COMMIT_SAMPLES: usize = (OPENAI_REALTIME_SAMPLE_RATE as usize) / 10;
const OPENAI_REALTIME_FINAL_TIMEOUT: Duration = Duration::from_secs(12);

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

struct RealtimePcmEncoder {
    input_sample_rate: u32,
    input_channels: usize,
    pending_mono: Vec<f32>,
    next_source_pos: f64,
}

impl RealtimePcmEncoder {
    fn new(input_sample_rate: u32, input_channels: u16) -> Self {
        Self {
            input_sample_rate,
            input_channels: input_channels.max(1) as usize,
            pending_mono: Vec::new(),
            next_source_pos: 0.0,
        }
    }

    fn push_f32(&mut self, input: &[f32]) -> Vec<i16> {
        if input.is_empty() {
            return Vec::new();
        }

        let frames = input.len() / self.input_channels;
        self.pending_mono.reserve(frames);
        for frame in 0..frames {
            let start = frame * self.input_channels;
            let sum: f32 = input[start..start + self.input_channels].iter().sum();
            self.pending_mono.push(sum / self.input_channels as f32);
        }

        self.drain_available(false)
    }

    fn finish(&mut self) -> Vec<i16> {
        self.drain_available(true)
    }

    fn drain_available(&mut self, flush: bool) -> Vec<i16> {
        if self.pending_mono.is_empty() {
            return Vec::new();
        }

        let step = self.input_sample_rate as f64 / OPENAI_REALTIME_SAMPLE_RATE as f64;
        let mut output = Vec::new();

        while self.next_source_pos + 1.0 < self.pending_mono.len() as f64
            || (flush && self.next_source_pos < self.pending_mono.len() as f64)
        {
            let idx = self.next_source_pos.floor() as usize;
            let frac = self.next_source_pos - idx as f64;
            let current = self.pending_mono[idx];
            let next = self.pending_mono.get(idx + 1).copied().unwrap_or(current);
            let sample = current + (next - current) * frac as f32;
            output.push(f32_to_i16(sample));
            self.next_source_pos += step;
        }

        let consumed = self.next_source_pos.floor() as usize;
        if consumed > 0 {
            let drain_to = consumed.min(self.pending_mono.len());
            self.pending_mono.drain(0..drain_to);
            self.next_source_pos -= drain_to as f64;
        }

        if flush {
            self.pending_mono.clear();
            self.next_source_pos = 0.0;
        }

        output
    }
}

fn f32_to_i16(sample: f32) -> i16 {
    (sample * 32767.0).clamp(-32768.0, 32767.0) as i16
}

type WsWrite = futures_util::stream::SplitSink<
    tokio_tungstenite::WebSocketStream<tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>>,
    Message,
>;

async fn send_realtime_event(write: &mut WsWrite, event: Value) -> Result<()> {
    write
        .send(Message::Text(event.to_string().into()))
        .await
        .context("Failed to send OpenAI Realtime event")
}

async fn append_realtime_audio(write: &mut WsWrite, pcm_samples: &[i16]) -> Result<()> {
    if pcm_samples.is_empty() {
        return Ok(());
    }
    let mut pcm_bytes = Vec::with_capacity(pcm_samples.len() * 2);
    for sample in pcm_samples {
        pcm_bytes.extend_from_slice(&sample.to_le_bytes());
    }
    send_realtime_event(
        write,
        json!({
            "type": "input_audio_buffer.append",
            "audio": BASE64_STANDARD.encode(pcm_bytes),
        }),
    )
    .await
}

async fn commit_realtime_audio(write: &mut WsWrite) -> Result<()> {
    send_realtime_event(write, json!({ "type": "input_audio_buffer.commit" })).await
}

/// Processes one WebSocket message; returns true iff it was a completion event.
fn handle_realtime_message(
    message: Message,
    live_text: &mut String,
    final_parts: &mut Vec<String>,
) -> Result<bool> {
    let text = match message {
        Message::Text(text) => text,
        Message::Close(frame) => {
            debug!("OpenAI Realtime WebSocket closed: {:?}", frame);
            return Ok(false);
        }
        _ => return Ok(false),
    };
    let event: Value = serde_json::from_str(text.as_ref())
        .with_context(|| format!("Failed to parse OpenAI Realtime event: {}", text))?;
    match event.get("type").and_then(Value::as_str).unwrap_or_default() {
        "conversation.item.input_audio_transcription.delta" => {
            if let Some(delta) = event.get("delta").and_then(Value::as_str) {
                print!("{}", delta);
                io::stdout().flush().ok();
                live_text.push_str(delta);
            }
            Ok(false)
        }
        "conversation.item.input_audio_transcription.completed" => {
            let transcript = event
                .get("transcript")
                .and_then(Value::as_str)
                .unwrap_or_default()
                .trim();
            if !transcript.is_empty() {
                final_parts.push(transcript.to_string());
            }
            Ok(true)
        }
        "error" => {
            let msg = event
                .pointer("/error/message")
                .and_then(Value::as_str)
                .unwrap_or("unknown OpenAI Realtime error");
            Err(anyhow!("OpenAI Realtime error: {}", msg))
        }
        event_type => {
            debug!("OpenAI Realtime event: {}", event_type);
            Ok(false)
        }
    }
}

pub async fn transcribe_openai_realtime(
    config: Arc<Config>,
    mut audio_rx: mpsc::UnboundedReceiver<Vec<f32>>,
    input_sample_rate: u32,
    input_channels: u16,
) -> Result<String> {
    if config.api_key.is_empty() {
        return Err(anyhow!(
            "OpenAI API key is missing. Please provide it via --api-key or OPENAI_API_KEY env var."
        ));
    }

    let mut request = OPENAI_REALTIME_WS_URL
        .into_client_request()
        .context("Failed to build OpenAI Realtime WebSocket request")?;
    request.headers_mut().insert(
        "Authorization",
        format!("Bearer {}", config.api_key)
            .parse()
            .context("Failed to build OpenAI authorization header")?,
    );

    let (ws_stream, _) = connect_async(request)
        .await
        .context("Failed to connect to OpenAI Realtime API")?;
    let (mut write, mut read) = ws_stream.split();

    send_realtime_event(
        &mut write,
        json!({
            "type": "session.update",
            "session": {
                "type": "transcription",
                "audio": {
                    "input": {
                        "format": {
                            "type": "audio/pcm",
                            "rate": OPENAI_REALTIME_SAMPLE_RATE
                        },
                        "transcription": {
                            "model": OPENAI_REALTIME_TRANSCRIPTION_MODEL,
                            "language": "en",
                            "delay": "low"
                        },
                        "turn_detection": null
                    }
                }
            }
        }),
    )
    .await?;

    info!(
        "OpenAI Realtime transcription connected (transcription model: {}, input: {}Hz {}ch -> {}Hz mono PCM16).",
        OPENAI_REALTIME_TRANSCRIPTION_MODEL,
        input_sample_rate,
        input_channels,
        OPENAI_REALTIME_SAMPLE_RATE
    );

    let mut encoder = RealtimePcmEncoder::new(input_sample_rate, input_channels);
    let mut commit_interval = tokio::time::interval(OPENAI_REALTIME_COMMIT_INTERVAL);
    commit_interval.tick().await; // discard the immediate first tick
    let mut pending_samples = 0usize;
    let mut commits_sent = 0usize;
    let mut completions_seen = 0usize;
    let mut live_text = String::new();
    let mut final_parts: Vec<String> = Vec::new();

    // Streaming phase: pump audio in and drain events out until the recorder
    // closes the audio channel.
    loop {
        tokio::select! {
            chunk = audio_rx.recv() => {
                let Some(chunk) = chunk else { break };
                let pcm = encoder.push_f32(&chunk);
                if !pcm.is_empty() {
                    append_realtime_audio(&mut write, &pcm).await?;
                    pending_samples += pcm.len();
                }
            }
            _ = commit_interval.tick() => {
                if pending_samples >= OPENAI_REALTIME_MIN_COMMIT_SAMPLES {
                    commit_realtime_audio(&mut write).await?;
                    commits_sent += 1;
                    pending_samples = 0;
                }
            }
            maybe_message = read.next() => {
                let Some(message) = maybe_message else { break };
                let message = message.context("OpenAI Realtime WebSocket read failed")?;
                if handle_realtime_message(message, &mut live_text, &mut final_parts)? {
                    completions_seen += 1;
                }
            }
        }
    }

    // Flush trailing samples. Skip the commit if the tail is shorter than
    // OpenAI's minimum — a sub-100ms commit returns a fatal error event that
    // would otherwise discard the entire transcript.
    let tail = encoder.finish();
    if !tail.is_empty() {
        append_realtime_audio(&mut write, &tail).await?;
        pending_samples += tail.len();
    }
    if pending_samples >= OPENAI_REALTIME_MIN_COMMIT_SAMPLES {
        commit_realtime_audio(&mut write).await?;
        commits_sent += 1;
    }

    // Finalization phase: wait for any in-flight completions, bounded by one
    // absolute deadline (pinned, so it doesn't reset on each event).
    let deadline = sleep(OPENAI_REALTIME_FINAL_TIMEOUT);
    tokio::pin!(deadline);
    while completions_seen < commits_sent {
        tokio::select! {
            _ = &mut deadline => {
                warn!(
                    "Timed out waiting for OpenAI Realtime final transcription events ({} of {} received).",
                    completions_seen, commits_sent
                );
                break;
            }
            maybe_message = read.next() => {
                let Some(message) = maybe_message else { break };
                let message = message.context("OpenAI Realtime WebSocket read failed")?;
                if handle_realtime_message(message, &mut live_text, &mut final_parts)? {
                    completions_seen += 1;
                }
            }
        }
    }

    let final_text = if final_parts.is_empty() {
        live_text
    } else {
        final_parts.join(" ")
    };
    Ok(final_text.trim().to_string())
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
                "Retrying OpenAI API call (attempt {}) after {:?}",
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
                    let result = resp
                        .json::<OpenAIResponse>()
                        .await
                        .context("Failed to parse OpenAI JSON response")?;
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
