use anyhow::{Context, Result};
use cpal::StreamConfig;
use log::{debug, error, info, warn};
use std::path::PathBuf;
use std::process::exit;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::{mpsc, Mutex}; // Use tokio's async Mutex

mod api;
mod audio;
mod config;
mod hotkey;
mod output;
mod utils; // For cache dir etc.

use config::{Config, OutputType, Service};

// Shared application state
struct AppState {
    is_recording: bool,
    // Potentially other things that need to be shared safely
}

// Global cancellation token
static IS_RUNNING: AtomicBool = AtomicBool::new(true);

#[tokio::main]
async fn main() -> Result<()> {
    env_logger::init(); // Initialize logging based on RUST_LOG env var

    // --- Argument Parsing ---
    let config = Config::parse();
    debug!("Parsed Config: {:?}", config);

    // --- Validate Configuration ---
    if config.output == OutputType::File && config.file.is_none() {
        anyhow::bail!("Output mode 'file' requires the --file argument.");
    }
    if config.api_key.is_empty() {
        anyhow::bail!(
            "API key not provided via --api-key or environment variable ({}).",
            config.service.get_env_var_name()
        );
    }
    if config.service == Service::Replicate && config.api_key.starts_with("sk") {
        warn!("API key looks like an ElevenLabs key, but Replicate service is selected.");
    } else if config.service == Service::OpenAI && !config.api_key.starts_with("sk-") {
        warn!("API key does not look like an OpenAI key (should start with 'sk-'), but OpenAI service is selected.");
    }
    // Add more validation as needed

    let config = Arc::new(config); // Share config immutably

    // --- Setup State & Communication Channels ---
    let app_state = Arc::new(Mutex::new(AppState {
        is_recording: false,
    }));
    // Channel for hotkey events -> main loop
    let (hotkey_tx, mut hotkey_rx) = mpsc::channel::<hotkey::HotkeyEvent>(32);
    // Channel for main loop -> audio recorder control (optional, could use state)
    // let (audio_cmd_tx, audio_cmd_rx) = mpsc::channel...

    // --- Setup Ctrl+C Handler ---
    ctrlc::set_handler(|| {
        info!("Ctrl+C detected. Shutting down...");
        IS_RUNNING.store(false, Ordering::SeqCst);
    })
    .context("Error setting Ctrl+C handler")?;

    // --- Start Hotkey Listener ---
    let listener_config = config.clone();
    let listener_tx = hotkey_tx.clone();
    tokio::task::spawn_blocking(move || {
        info!("Starting hotkey listener...");
        if let Err(e) = hotkey::listen_for_hotkeys(listener_config, listener_tx) {
            error!("Hotkey listener failed: {}", e);
            // Signal shutdown? Or maybe just proceed without hotkeys?
            IS_RUNNING.store(false, Ordering::SeqCst);
        }
        info!("Hotkey listener thread finished.");
    });

    // --- Initialize Audio Recorder ---
    let mut recorder = audio::AudioRecorder::new(config.max_time)
        .context("Failed to initialize audio recorder")?;
    let cache_dir = utils::get_cache_dir()?.join("audio_recordings");
    tokio::fs::create_dir_all(&cache_dir) // Use tokio's async fs
        .await
        .context("Failed to create cache directory")?;
    info!("Using cache directory: {}", cache_dir.display());

    // --- Main Application Loop ---
    info!(
        "Whisper Dictation Ready. Press hotkey ({}:{}) to toggle.",
        config.modifier, config.key
    );
    info!("Press Ctrl+C to quit.");

    // Fallback stdin listener (simple version) - Runs in background
    let stdin_tx = hotkey_tx.clone();
    tokio::spawn(async move {
        let mut stdin = tokio::io::stdin();
        let mut line = String::new();
        loop {
            // Check if still running
            if !IS_RUNNING.load(Ordering::Relaxed) {
                break;
            }
            // Attempt to read line async, maybe with timeout? Simple read for now.
            match tokio::io::AsyncBufReadExt::read_line(
                &mut tokio::io::BufReader::new(&mut stdin),
                &mut line,
            )
            .await
            {
                Ok(_) => {
                    info!("Enter detected in terminal. Requesting toggle.");
                    if stdin_tx
                        .send(hotkey::HotkeyEvent::ToggleRecording)
                        .await
                        .is_err()
                    {
                        error!("Failed to send toggle event from stdin.");
                        break;
                    }
                    line.clear(); // Clear buffer for next read
                }
                Err(_) => {
                    debug!("Stdin closed or error reading line.");
                    break; // Exit task if stdin fails
                }
            }
        }
        info!("Stdin listener task finished.");
    });

    while IS_RUNNING.load(Ordering::Relaxed) {
        tokio::select! {
            _ = tokio::time::sleep(Duration::from_millis(50)) => {
            }
            Some(event) = hotkey_rx.recv() => {
                match event {
                    hotkey::HotkeyEvent::ToggleRecording => {
                        let mut state = app_state.lock().await; // Lock the state
                        let currently_recording = state.is_recording;
                         state.is_recording = !currently_recording;
                         let should_be_recording = state.is_recording;
                         // Unlock happens automatically when `state` goes out of scope

                        if should_be_recording {
                            info!(">>> Starting recording... <<<");
                            recorder.start().unwrap();
                        } else {
                             info!(">>> Stopping recording and processing... <<<");
                            match recorder.stop() {
                                Ok(Some((stream_config, audio_data))) => {
                                    info!("Recording stopped. Got {} samples.", audio_data.len());
                                     // Process in background task not to block main loop
                                     let task_config = config.clone();
                                     let task_cache_dir = cache_dir.clone();
                                     tokio::spawn(async move {
                                         process_recorded_audio(task_config, task_cache_dir, stream_config, audio_data).await;
                                     });
                                }
                                Ok(None) => {
                                     warn!("Recording stopped but no audio data captured.");
                                }
                                Err(e) => {
                                     error!("Error stopping recording: {}", e);
                                }
                             }
                         }
                     }
                 }
             }
        }
    } // End main loop

    info!("Main loop finished. Cleaning up...");
    // Cleanup resources (recorder, threads - though tokio handles task cancellation)
    // Ensure running flag is false so background threads know to stop
    IS_RUNNING.store(false, Ordering::SeqCst);

    // Optional: Clean up old temp files
    match utils::cleanup_old_files(&cache_dir, Duration::from_secs(24 * 3600)).await {
        Ok(count) => info!("Cleaned up {} old temporary audio files.", count),
        Err(e) => warn!("Error during temporary file cleanup: {}", e),
    }

    info!("Whisper Dictation finished.");
    exit(0);
}

// Function to handle processing audio data (can be spawned as a task)
async fn process_recorded_audio(
    config: Arc<Config>,
    cache_dir: PathBuf,
    stream_config: StreamConfig,
    audio_data: Vec<f32>,
) {
    // 1. Save to WAV
    let filename = format!("recording_{}.wav", chrono::Utc::now().timestamp_millis());
    let wav_path = cache_dir.join(&filename);
    info!("Saving audio to: {}", wav_path.display());

    match audio::save_f32_to_wav(
        &wav_path,
        &audio_data,
        stream_config.sample_rate.0,
        stream_config.channels,
    ) {
        Ok(_) => {
            info!("Audio saved successfully.");
            // 2. Transcribe using API
            let transcription_result = match config.service {
                Service::OpenAI => api::transcribe_openai(&config, &wav_path).await,
                Service::Replicate => api::transcribe_replicate(&config, &wav_path).await,
                Service::ElevenLabs => {
                    api::transcribe_elevenlabs(&config, &wav_path.as_path()).await
                }
            };

            match transcription_result {
                Ok(text) => {
                    if !text.is_empty() {
                        info!(
                            "Transcription successful: {}...",
                            text.chars().take(50).collect::<String>()
                        );
                        // 3. Process Output
                        if let Err(e) = output::process_output(&config, &text.as_str()).await {
                            error!("Failed to process output: {}", e);
                        }
                    } else {
                        warn!("API returned an empty transcription.");
                    }
                }
                Err(e) => {
                    error!("API transcription failed: {}", e);
                }
            }

            // 4. Clean up temporary WAV file
            match tokio::fs::remove_file(&wav_path).await {
                Ok(_) => debug!("Removed temporary file: {}", wav_path.display()),
                Err(e) => warn!(
                    "Failed to remove temporary file {}: {}",
                    wav_path.display(),
                    e
                ),
            }
        }
        Err(e) => {
            error!("Failed to save WAV file {}: {}", wav_path.display(), e);
        }
    }
}
