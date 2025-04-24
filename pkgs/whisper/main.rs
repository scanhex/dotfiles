Okay, translating this Python script to Rust is a significant undertaking, involving asynchronous operations, platform-specific handling, audio processing, and interacting with external APIs and system utilities.

Here's a breakdown of the Rust implementation strategy and a conceptual structure. Due to the complexity, a direct line-by-line translation isn't feasible or efficient. I'll provide the core structure, dependency setup, and implementations for key parts, focusing on the requested libraries (`rdev`, `enigo`) and the Wayland challenge.

**1. Project Setup (`Cargo.toml`)**

```toml
[package]
name = "rust_whisper_dictation"
version = "0.1.0"
edition = "2021"

[dependencies]
# Core Async Runtime
tokio = { version = "1", features = ["full"] }

# Argument Parsing
clap = { version = "4", features = ["derive", "env"] }

# Audio Input/Output
cpal = "0.15"
hound = "3.5" # WAV file handling

# Hotkey Listening (Cross-platform except Wayland needs manual)
rdev = "0.5"

# Wayland Input Event Handling (Linux Only)
# This crate provides raw input event access
input-linux = { version = "0.6", optional = true }
input-linux-sys = { version = "0.8", optional = true } # Needed for specific types/constants
libc = { version = "0.2", optional = true } # For polling/file descriptors on Linux

# Keyboard/Mouse Simulation
enigo = "0.2"

# HTTP Client
reqwest = { version = "0.12", features = ["json", "multipart", "stream"] }

# JSON Handling
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# Clipboard
arboard = "3"

# Base64 Encoding
base64 = "0.22"

# Filesystem & Paths
std = "1" # Implicit, but good to remember
tempfile = "3"
directories = "5" # Cross-platform directory locations

# Signal Handling
ctrlc = { version = "3", features = ["termination"] }

# Logging
log = "0.4"
env_logger = "0.11"

# Error Handling convenience
anyhow = "1" # Or use thiserror for library-style errors

# Platform-specific helpers (only if needed for finding tools)
which = { version = "6", optional = true }

[target.'cfg(target_os = "linux")'.dependencies]
# Activate these deps only for Linux builds
input-linux = { version = "0.6" }
input-linux-sys = { version = "0.8" }
libc = "0.2"
which = "6"

[features]
# Feature to explicitly enable Wayland support build
wayland = ["input-linux", "input-linux-sys", "libc", "which"]
```

**2. Main Structure (`src/main.rs`)**

```rust
use anyhow::{Context, Result};
use clap::Parser;
use log::{debug, error, info, warn};
use std::path::PathBuf;
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
         anyhow::bail!("API key not provided via --api-key or environment variable ({}).", config.service.get_env_var_name());
    }
    if config.service == Service::Replicate && config.api_key.starts_with("sk-") {
        // Basic check, Replicate uses tokens, ElevenLabs uses sk-...
        warn!("API key looks like an ElevenLabs key, but Replicate service is selected.");
    }
    // Add more validation as needed

    let config = Arc::new(config); // Share config immutably

    // --- Setup State & Communication Channels ---
    let app_state = Arc::new(Mutex::new(AppState { is_recording: false }));
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
    let cache_dir = utils::get_cache_dir()?
        .join("audio_recordings");
    tokio::fs::create_dir_all(&cache_dir) // Use tokio's async fs
        .await
        .context("Failed to create cache directory")?;
    info!("Using cache directory: {}", cache_dir.display());


    // --- Main Application Loop ---
    info!("Whisper Dictation Ready. Press hotkey ({}:{}) to toggle.",
          config.modifier, config.key);
    info!("Press Enter in the *original* terminal (if no hotkey active) as fallback.");
    info!("Press Ctrl+C to quit.");

    // Fallback stdin listener (simple version) - Runs in background
    let stdin_tx = hotkey_tx.clone();
     tokio::spawn(async move {
        let mut stdin = tokio::io::stdin();
        let mut line = String::new();
         loop {
             // Check if still running
             if !IS_RUNNING.load(Ordering::Relaxed) { break; }
            // Attempt to read line async, maybe with timeout? Simple read for now.
             match tokio::io::AsyncBufReadExt::read_line(&mut tokio::io::BufReader::new(&mut stdin), &mut line).await {
                 Ok(_) => {
                     info!("Enter detected in terminal. Requesting toggle.");
                     if stdin_tx.send(hotkey::HotkeyEvent::ToggleRecording).await.is_err() {
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
            // Listen for hotkey events
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
                            recorder.start().context("Failed to start recording")?; // Handle error
                        } else {
                             info!(">>> Stopping recording and processing... <<<");
                            match recorder.stop() {
                                Ok(Some(audio_data)) => {
                                    info!("Recording stopped. Got {} samples.", audio_data.len());
                                     // Process in background task not to block main loop
                                     let task_config = config.clone();
                                     let task_cache_dir = cache_dir.clone();
                                     tokio::spawn(async move {
                                         process_recorded_audio(task_config, task_cache_dir, audio_data).await;
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
             // Add other events to select! if needed (e.g., UI events, timer)

             // Small delay to prevent busy-looping when no events
            _ = tokio::time::sleep(Duration::from_millis(50)) => {
                 // Just continue the loop
            }

             // Check if should exit
             else => { // This branch is taken if hotkey_rx closes OR all other branches are disabled/pending forever.
                 if !IS_RUNNING.load(Ordering::Relaxed) {
                     info!("Shutdown signal received in main loop.");
                     break;
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
    Ok(())
}


// Function to handle processing audio data (can be spawned as a task)
async fn process_recorded_audio(config: Arc<Config>, cache_dir: PathBuf, audio_data: Vec<f32>) {
    // 1. Save to WAV
    let filename = format!("recording_{}.wav", chrono::Utc::now().timestamp_millis());
    let wav_path = cache_dir.join(&filename);
    info!("Saving audio to: {}", wav_path.display());

    match audio::save_f32_to_wav(&wav_path, &audio_data, audio::SAMPLE_RATE, audio::CHANNELS) {
        Ok(_) => {
             info!("Audio saved successfully.");
            // 2. Transcribe using API
             let transcription_result = match config.service {
                 Service::Replicate => api::transcribe_replicate(&config, &wav_path).await,
                 Service::ElevenLabs => api::transcribe_elevenlabs(&config, &wav_path).await,
             };

             match transcription_result {
                 Ok(text) => {
                     if !text.is_empty() {
                         info!("Transcription successful: {}...", text.chars().take(50).collect::<String>());
                        // 3. Process Output
                         if let Err(e) = output::process_output(&config, &text).await {
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
                 Err(e) => warn!("Failed to remove temporary file {}: {}", wav_path.display(), e),
             }
        }
        Err(e) => {
            error!("Failed to save WAV file {}: {}", wav_path.display(), e);
        }
    }
}


```

**3. Configuration (`src/config.rs`)**

```rust
use clap::{Parser, ValueEnum};
use std::path::PathBuf;

#[derive(Parser, Debug, Clone)]
#[command(author, version, about = "Whisper Dictation (Rust) - Dictate and paste via APIs")]
pub struct Config {
    /// API key/token for the selected service. Can also be set via environment variables:
    /// ELEVENLABS_API_KEY or REPLICATE_API_TOKEN
    #[arg(short, long, env = "API_KEY_PLACEHOLDER", hide_env_values = true)] // Placeholder, specific env handled dynamically
    pub api_key_arg: Option<String>,

    /// Speech-to-text service to use
    #[arg(short, long, value_enum, default_value_t = Service::ElevenLabs, env = "DICTATION_SERVICE")]
    pub service: Service,

    /// Output mode
    #[arg(short, long, value_enum, default_value_t = OutputType::Clipboard, env = "DICTATION_OUTPUT")]
    pub output: OutputType,

    /// Output file path (required for 'file' output mode)
    #[arg(short, long, env = "DICTATION_FILE")]
    pub file: Option<PathBuf>,

    /// Modifier key for hotkey (e.g., Control, Alt, Shift, Meta/Super/Win/Cmd)
    #[arg(short = 'm', long, default_value = "Control", env = "DICTATION_MOD")]
    pub modifier: String, // Keep as String for flexibility, parse in hotkey module

    /// Main key for hotkey (e.g., F11, A, Space, Enter) - Case Insensitive
    #[arg(short = 'g', long, default_value = "F11", env = "DICTATION_KEY")]
    pub key: String, // Keep as String, parse in hotkey module

    /// Number of API retries on failure
    #[arg(short, long, default_value_t = 3, env = "DICTATION_RETRIES")]
    pub retries: u32,

    /// Maximum recording time in seconds
    #[arg(long, default_value_t = 60, env = "DICTATION_MAX_TIME")]
    pub max_time: u32,

    // --- Resolved values (populated after parsing) ---
    #[clap(skip)]
    pub api_key: String,
}

#[derive(Debug, Clone, Copy, ValueEnum, PartialEq, Eq)]
pub enum Service {
    Replicate,
    ElevenLabs,
}

impl Service {
    pub fn get_env_var_name(&self) -> &'static str {
        match self {
            Service::Replicate => "REPLICATE_API_TOKEN",
            Service::ElevenLabs => "ELEVENLABS_API_KEY",
        }
    }
}

#[derive(Debug, Clone, Copy, ValueEnum, PartialEq, Eq)]
pub enum OutputType {
    Clipboard,
    Paste,
    File,
    Stdout,
}

// Implement logic to populate api_key after parsing args
impl Config {
     pub fn parse() -> Self {
        let mut conf = <Self as Parser>::parse();
        let env_var_name = conf.service.get_env_var_name();
        conf.api_key = conf.api_key_arg
            .clone()
            .or_else(|| std::env::var(env_var_name).ok())
            .unwrap_or_default(); // Defaults to empty string if none found
        conf
    }
}
```

**4. Audio Handling (`src/audio.rs`)**

```rust
use anyhow::{anyhow, Context, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{SampleFormat, SampleRate, Stream, StreamConfig};
use hound::{SampleFormat as HoundSampleFormat, WavSpec, WavWriter};
use log::{debug, info, warn};
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::Duration;

pub const SAMPLE_RATE: u32 = 16000;
pub const CHANNELS: u16 = 1;
// Choose f32 as it's common and APIs often prefer it. PyAudio used paFloat32.
const SAMPLE_FORMAT: SampleFormat = SampleFormat::F32;

pub struct AudioRecorder {
    // Store frames in an Arc<Mutex> to allow access from audio callback thread
    frames: Arc<Mutex<Vec<f32>>>,
    stream: Option<Stream>, // Keep the stream alive
    max_duration: Duration,
    max_frames: usize,
    is_recording_flag: Arc<Mutex<bool>>, // Flag to signal recording state
}

impl AudioRecorder {
    pub fn new(max_time_seconds: u32) -> Result<Self> {
        let max_duration = Duration::from_secs(max_time_seconds as u64);
        let max_frames = (SAMPLE_RATE * CHANNELS as u32 * max_time_seconds) as usize;
        info!(
            "Audio Recorder configured: {} Hz, {} channels, Max Duration: {:?}, Max Frames: {}",
            SAMPLE_RATE, CHANNELS, max_duration, max_frames
        );

        Ok(Self {
            frames: Arc::new(Mutex::new(Vec::with_capacity(max_frames))),
            stream: None,
            max_duration,
            max_frames,
            is_recording_flag: Arc::new(Mutex::new(false)),
        })
    }

    pub fn start(&mut self) -> Result<()> {
        if self.is_recording() {
            warn!("Recording already in progress.");
            return Ok(());
        }

        // Clear previous frames
        self.frames.lock().expect("Mutex poisoned").clear();

        let host = cpal::default_host();
        let device = host
            .default_input_device()
            .context("No default input device available")?;
        info!("Using audio input device: {}", device.name()?);

        let config = StreamConfig {
            channels: CHANNELS,
            sample_rate: SampleRate(SAMPLE_RATE),
            buffer_size: cpal::BufferSize::Default, // Or fixed size like 1024?
        };

        // Check if format is supported
        let supported_configs = device.supported_input_configs()?;
        let supported = supported_configs.filter(|c| {
            c.sample_format() == SAMPLE_FORMAT && c.channels() == CHANNELS && c.min_sample_rate() <= SampleRate(SAMPLE_RATE) && c.max_sample_rate() >= SampleRate(SAMPLE_RATE)
        }).next();

         if supported.is_none() {
             // Fallback check? Try nearest supported config?
              return Err(anyhow!(
                  "Default device does not support required format: {}Hz, {}ch, {:?}",
                 SAMPLE_RATE, CHANNELS, SAMPLE_FORMAT
             ));
          }
         info!("Device supports the required audio format.");

        let shared_frames = self.frames.clone();
        let max_frames = self.max_frames;
        let is_recording_flag_callback = self.is_recording_flag.clone();
        let stop_recording_flag_callback = self.is_recording_flag.clone(); // Need to access it to stop

        let err_fn = |err| error!("An error occurred on the audio stream: {}", err);

        let stream = device.build_input_stream(
            &config,
            move |data: &[f32], _: &cpal::InputCallbackInfo| {
                 // Check if we should still be recording
                 if !is_recording_flag_callback.lock().expect("Mutex poisoned").clone() {
                      // This might not immediately stop the stream, but prevents adding more data
                     return;
                 }


                let mut frame_buffer = shared_frames.lock().expect("Mutex poisoned");

                // Check if max duration reached
                if frame_buffer.len() >= max_frames {
                    if *is_recording_flag_callback.lock().expect("Mutex poisoned") {
                        warn!("Max recording time reached. Stopping capture.");
                         // Signal stopping (best effort, stream might run a bit longer)
                         *stop_recording_flag_callback.lock().expect("Mutex poisoned") = false;
                    }
                    return; // Don't add more frames
                 }

                // Append data, ensuring we don't exceed max_frames precisely
                 let space_left = max_frames - frame_buffer.len();
                 let elements_to_add = std::cmp::min(data.len(), space_left);
                frame_buffer.extend_from_slice(&data[..elements_to_add]);
            },
            err_fn,
            None, // Timeout - None means block indefinitely
        )?;

        stream.play()?;
        self.stream = Some(stream);
        *self.is_recording_flag.lock().expect("Mutex poisoned") = true;
        info!("Audio recording started.");

        Ok(())
    }

    pub fn stop(&mut self) -> Result<Option<Vec<f32>>> {
        // Signal the callback to stop adding data
        *self.is_recording_flag.lock().expect("Mutex poisoned") = false;

        if let Some(stream) = self.stream.take() {
            stream.pause()?; // Pausing might be enough, drop will close it
            drop(stream); // Ensure stream resources are released
            info!("Audio stream stopped and resources released.");
        } else {
            warn!("Stop called but no active stream found.");
             // Still return any captured data
         }

        let frames = self.frames.lock().expect("Mutex poisoned");
        if frames.is_empty() {
            Ok(None)
        } else {
            Ok(Some(frames.clone())) // Clone the data to return
        }
    }


    pub fn is_recording(&self) -> bool {
         *self.is_recording_flag.lock().expect("Mutex poisoned")
    }

    // Destructor not explicit in Rust, relies on Drop trait.
    // Stream dropping should handle cleanup.
}

// Helper function to save f32 samples to a WAV file
// Note: Standard WAV often uses Int16. APIs might accept float, but saving as Int16 is safer.
pub fn save_f32_to_wav(path: &Path, data: &[f32], sample_rate: u32, channels: u16) -> Result<()> {
    if data.is_empty() {
        return Err(anyhow!("No audio data to save."));
    }

    let spec = WavSpec {
        channels,
        sample_rate,
        bits_per_sample: 16, // Save as 16-bit integer PCM
        sample_format: HoundSampleFormat::Int,
    };

    let mut writer = WavWriter::create(path, spec)
        .with_context(|| format!("Failed to create WAV writer for '{}'", path.display()))?;

    // Convert f32 samples (-1.0 to 1.0) to i16 (-32768 to 32767)
    for &sample_f32 in data {
        let sample_i16 = (sample_f32 * 32767.0).clamp(-32768.0, 32767.0) as i16;
        writer.write_sample(sample_i16)?;
    }

    writer.finalize()?;
    debug!("Successfully saved {} samples to {}", data.len(), path.display());
    Ok(())
}

```

**5. Hotkey Handling (`src/hotkey.rs`)**

This is the most complex part, especially Wayland.

```rust
use crate::config::Config;
use anyhow::{anyhow, bail, Context, Result};
use log::{debug, error, info, warn};
use rdev::{listen, Event, EventType, Key, KeyboardState};
use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::mpsc::Sender as StdSender; // Use std mpsc for sync listener thread
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;
use tokio::sync::mpsc::Sender; // Use tokio mpsc for sending to async main loop

#[derive(Debug, Clone, Copy)]
pub enum HotkeyEvent {
    ToggleRecording,
}

// --- Platform Agnostic Listener ---
pub fn listen_for_hotkeys(config: Arc<Config>, tx: Sender<HotkeyEvent>) -> Result<()> {
    if cfg!(target_os = "linux") && is_wayland() {
        info!("Wayland detected. Attempting evdev-based listener.");
        #[cfg(feature = "wayland")]
        {
            listen_wayland(config, tx)
        }
        #[cfg(not(feature = "wayland"))]
        {
            bail!("Wayland detected, but the 'wayland' feature is not enabled in this build. Recompile with --features wayland.")
        }
    } else {
        info!("Using rdev listener (X11/Windows/macOS).");
        listen_rdev(config, tx)
    }
}

// --- rdev Listener (X11, Windows, macOS) ---
fn listen_rdev(config: Arc<Config>, tx: Sender<HotkeyEvent>) -> Result<()> {
    // Map config strings to rdev keys (needs careful parsing)
    let target_modifier = parse_modifier_rdev(&config.modifier)?;
    let target_key = parse_key_rdev(&config.key)?;
    info!(
        "rdev: Listening for Modifier: {:?}, Key: {:?}",
        target_modifier, target_key
    );

    let modifier_pressed = Arc::new(Mutex::new(false));
    let key_pressed = Arc::new(Mutex::new(false)); // Track main key state

    // Use std::sync::mpsc channel because rdev::listen is blocking
    let (std_tx, std_rx) = std::sync::mpsc::channel::<HotkeyEvent>();

    // Spawn rdev::listen in a separate thread
     let listen_thread = thread::spawn(move || {
         let mod_pressed_clone = modifier_pressed.clone();
         let key_pressed_clone = key_pressed.clone();
         let tx_clone = std_tx;

         let callback = move |event: Event| {
             match event.event_type {
                 EventType::KeyPress(key) => {
                    // Check modifier press
                     if key == target_modifier.0 || key == target_modifier.1 {
                         *mod_pressed_clone.lock().unwrap() = true;
                         // Reset key pressed state if modifier is re-pressed
                          *key_pressed_clone.lock().unwrap() = false;
                          debug!("rdev: Modifier {:?} pressed", key);
                     }
                    // Check target key press ONLY if modifier is ALREADY held
                     else if key == target_key {
                         let mut main_key_state = key_pressed_clone.lock().unwrap();
                         // Only trigger if main key wasn't already down AND modifier is down
                          if !*main_key_state && *mod_pressed_clone.lock().unwrap() {
                              debug!("rdev: Target key {:?} pressed with modifier held", key);
                             // Send toggle event
                              if tx_clone.send(HotkeyEvent::ToggleRecording).is_err() {
                                  error!("rdev: Failed to send toggle event from callback.");
                                  // Consider how to signal failure or stop listening
                              }
                               *main_key_state = true; // Mark main key as pressed
                           } else if *main_key_state {
                               debug!("rdev: Target key {:?} already held down.", key);
                           } else {
                               debug!("rdev: Target key {:?} pressed WITHOUT modifier held.", key);
                           }
                     } else {
                         // Another key pressed, ignore for hotkey logic but could log
                          // debug!("rdev: Other key pressed: {:?}", key);
                     }
                 }
                 EventType::KeyRelease(key) => {
                     // Check modifier release
                     if key == target_modifier.0 || key == target_modifier.1 {
                         *mod_pressed_clone.lock().unwrap() = false;
                         // Also reset the main key state when modifier is released
                          *key_pressed_clone.lock().unwrap() = false;
                          debug!("rdev: Modifier {:?} released", key);
                     }
                    // Check target key release
                     else if key == target_key {
                         *key_pressed_clone.lock().unwrap() = false;
                         debug!("rdev: Target key {:?} released", key);
                    } else {
                         // Other key released
                    }
                 }
                 _ => (), // Ignore mouse/other events
             }
         };

          info!("rdev listener thread starting blocking listen loop...");
         if let Err(error) = listen(callback) {
             error!("rdev Error: {:?}", error)
             // Signal error?
          }
          info!("rdev listener thread finished."); // Should ideally only happen on error/shutdown
      });


    // Bridge from std::sync::mpsc to tokio::sync::mpsc
    let bridge_tx = tx.clone();
    tokio::spawn(async move {
        while let Ok(event) = std_rx.recv() {
             if !crate::IS_RUNNING.load(std::sync::atomic::Ordering::Relaxed) {
                 break; // Stop bridging if app is shutting down
             }
            if bridge_tx.send(event).await.is_err() {
                error!("Failed to bridge hotkey event to main loop.");
                break;
            }
        }
        info!("Hotkey bridge task finished.");
    });

     // Keep main thread alive or let listen_thread run?
     // Let the main loop handle lifetime via IS_RUNNING flag
     // The listen_thread might block indefinitely until an error occurs.
     // Need a way to potentially interrupt it if IS_RUNNING becomes false?
     // rdev doesn't seem to offer a non-blocking poll or stop mechanism easily.

    Ok(())
}

// --- Wayland / evdev Listener (Linux Only) ---
#[cfg(feature = "wayland")]
fn listen_wayland(config: Arc<Config>, tx: Sender<HotkeyEvent>) -> Result<()> {
    use input_linux::{
        sys::{input_event, timeval}, // Use raw C structs
        EventKind, InputEvent, KeyState, EventTime, InputId, KeyId, // Use abstractions when possible
    };
    use input_linux_sys as sys; // Alias for ecodes
    use libc::{poll, pollfd, nfds_t, POLLIN};
    use std::fs::{self, File, OpenOptions};
    use std::io;
    use std::mem::size_of;
    use std::os::unix::io::{AsRawFd, FromRawFd, RawFd};
    use std::sync::mpsc::Sender as StdSender;
    // Bridge thread needed again for tokio mpsc
    let (std_tx, std_rx) = std::sync::mpsc::channel::<HotkeyEvent>();

    let target_modifier_codes = parse_modifier_evdev(&config.modifier)?;
    let target_key_code = parse_key_evdev(&config.key)?;
     info!(
        "evdev: Listening for Modifier Codes: {:?}, Key Code: {:?}",
        target_modifier_codes, target_key_code
     );

    // Thread to handle evdev reading
    let evdev_thread = thread::spawn(move || -> Result<()> {
        let mut devices: HashMap<PathBuf, File> = HashMap::new();
        let mut poll_fds: Vec<pollfd> = Vec::new();
        let modifier_pressed = Arc::new(Mutex::new(false)); // State per listener thread

         // Function to update devices and pollfds
         let mut update_devices = |devices: &mut HashMap<PathBuf, File>, poll_fds: &mut Vec<pollfd>| -> Result<()> {
            let current_device_paths: HashSet<PathBuf> = list_input_devices()?
                .into_iter()
                .filter(|p| p.file_name().map_or(false, |n| n.to_string_lossy().starts_with("event")))
                .collect();

            let known_paths: HashSet<PathBuf> = devices.keys().cloned().collect();

            // Remove disconnected devices
            for path in known_paths.difference(&current_device_paths) {
                info!("evdev: Device disconnected: {}", path.display());
                devices.remove(path);
            }

            // Add new potential keyboards
            for path in current_device_paths.difference(&known_paths) {
                 match open_evdev_device(path) {
                     Ok(Some(file)) => {
                         info!("evdev: Added keyboard device: {}", path.display());
                        devices.insert(path.clone(), file);
                     }
                     Ok(None) => { /* Not a keyboard, ignore */ }
                     Err(e) => {
                        // Log permission errors etc.
                         warn!("evdev: Failed to add device {}: {}", path.display(), e);
                     }
                 }
            }

             // Rebuild poll_fds from current devices
             poll_fds.clear();
             for file in devices.values() {
                 poll_fds.push(pollfd {
                     fd: file.as_raw_fd(),
                     events: POLLIN,
                     revents: 0,
                 });
             }
             Ok(())
         };


        // Initial device scan
        update_devices(&mut devices, &mut poll_fds)?;
        if devices.is_empty() {
             warn!("evdev: No suitable input devices found. Ensure you have read permissions for /dev/input/event* (add user to 'input' group?).")
             // Keep polling for new devices...
         }

        let mut buffer = [0u8; size_of::<input_event>() * 64]; // Read multiple events at once

         while crate::IS_RUNNING.load(std::sync::atomic::Ordering::Relaxed) {
             // Periodically update device list (e.g., every 5 seconds)
             // More robust would be using udev monitoring if possible
             // Simple periodic scan for now:
             // TODO: implement timer check for update_devices call

             if poll_fds.is_empty() {
                 thread::sleep(Duration::from_secs(1));
                 if let Err(e) = update_devices(&mut devices, &mut poll_fds) {
                    error!("evdev: Error updating devices: {}", e);
                 }
                 continue;
             }

             // Poll for events with timeout (e.g., 200ms)
            let num_events = unsafe { poll(poll_fds.as_mut_ptr(), poll_fds.len() as nfds_t, 200) };

            if num_events < 0 {
                let err = io::Error::last_os_error();
                if err.kind() == io::ErrorKind::Interrupted { continue; } // Interrupted by signal, safe to retry
                 error!("evdev: poll error: {}", err);
                 thread::sleep(Duration::from_secs(1)); // Avoid spamming errors
                 continue;
             }

             if num_events == 0 { continue; } // Timeout, no events

             // Process events from ready file descriptors
             let mut device_to_remove: Option<PathBuf> = None;
            for pfd in &poll_fds {
                if pfd.revents & POLLIN != 0 {
                    let path = devices.iter().find(|(_, file)| file.as_raw_fd() == pfd.fd)
                             .map(|(p, _)| p.clone()); // Find path by fd

                    if let Some(p) = path.as_ref() {
                         let device_file = devices.get_mut(p).unwrap(); // Should exist

                         match read_evdev_events(device_file, &mut buffer) {
                            Ok(events) => {
                                for event in events {
                                    if !crate::IS_RUNNING.load(std::sync::atomic::Ordering::Relaxed) { return Ok(()); }

                                     if let EventKind::Key(key_id) = event.kind() {
                                         let key_code = key_id.to_raw(); // Get u16 code
                                         let is_pressed = event.value() == 1 || event.value() == 2; // 1=press, 2=repeat
                                         let is_released = event.value() == 0;

                                          // Check Modifier state change
                                          if target_modifier_codes.contains(&key_code) {
                                               // Re-evaluate overall modifier state based on *current* pressed modifiers
                                               // This is simplified: Assume state based on this single event
                                               // A more robust way tracks state of *all* modifier keys
                                                if is_pressed {
                                                   *modifier_pressed.lock().unwrap() = true;
                                                    debug!("evdev: Modifier {:?} pressed/repeat", key_code);
                                                } else if is_released {
                                                    // Simple: assume released if *any* target mod key is released
                                                    // Correct way needs to check if *all* are released.
                                                     *modifier_pressed.lock().unwrap() = false;
                                                     debug!("evdev: Modifier {:?} released", key_code);
                                                }
                                          }
                                          // Check Target Key press *while* modifier is held
                                          else if key_code == target_key_code && is_pressed {
                                               if *modifier_pressed.lock().unwrap() {
                                                    debug!("evdev: Target key {:?} pressed/repeat with modifier", key_code);
                                                     // Send toggle event
                                                     if std_tx.send(HotkeyEvent::ToggleRecording).is_err() {
                                                         error!("evdev: Failed to send toggle event.");
                                                         // Consider how to handle this channel break
                                                         return Err(anyhow!("Failed to send to main thread"));
                                                     }
                                                    // Optional: Prevent repeat triggers? Need to track key down state.
                                                } else {
                                                     debug!("evdev: Target key {:?} pressed/repeat WITHOUT modifier", key_code);
                                                 }
                                          }
                                    }
                                }
                            }
                            Err(e) => {
                                if e.kind() == io::ErrorKind::WouldBlock || e.kind() == io::ErrorKind::Interrupted {
                                      continue; // Not really errors in non-blocking read
                                 } else if e.kind() == io::ErrorKind::NotConnected || e.kind() == io::ErrorKind::NotFound {
                                     // Device likely unplugged
                                      warn!("evdev: Device {} disconnected or error: {}", p.display(), e);
                                     device_to_remove = Some(p.clone());
                                 } else {
                                      error!("evdev: Error reading from {}: {}", p.display(), e);
                                     device_to_remove = Some(p.clone());
                                 }
                             }
                         }
                     }
                } // End processing ready descriptor

            // Remove device outside loop if needed
            if let Some(path_to_remove) = device_to_remove {
                devices.remove(&path_to_remove);
                // Need to rebuild poll_fds after removal
                 if let Err(e) = update_devices(&mut devices, &mut poll_fds) {
                     error!("evdev: Error updating devices after removal: {}", e);
                 }
            }

        } // End while IS_RUNNING

        info!("evdev listener thread finished.");
        Ok(())
    }); // End evdev thread spawn

    // Bridge thread (same as rdev)
    let bridge_tx = tx.clone();
    tokio::spawn(async move {
        while let Ok(event) = std_rx.recv() {
            if !crate::IS_RUNNING.load(std::sync::atomic::Ordering::Relaxed) { break; }
            if bridge_tx.send(event).await.is_err() {
                error!("Failed to bridge evdev hotkey event to main loop.");
                break;
            }
        }
        info!("evdev Hotkey bridge task finished.");
    });

    // Need join handle or similar if main thread needs to ensure cleanup?
    // For now, rely on IS_RUNNING flag.

    Ok(())
}


// --- Helper Functions ---

fn is_wayland() -> bool {
    std::env::var("WAYLAND_DISPLAY").is_ok()
}


fn parse_modifier_rdev(mod_str: &str) -> Result<(Key, Key)> {
    match mod_str.to_lowercase().as_str() {
        "ctrl" | "control" => Ok((Key::ControlLeft, Key::ControlRight)),
        "alt" => Ok((Key::Alt, Key::AltGr)), // AltGr might be Right Alt
        "shift" => Ok((Key::ShiftLeft, Key::ShiftRight)),
        "meta" | "super" | "win" | "cmd" | "command" => Ok((Key::MetaLeft, Key::MetaRight)),
        _ => Err(anyhow!("Unsupported rdev modifier string: {}", mod_str)),
    }
}

fn parse_key_rdev(key_str: &str) -> Result<Key> {
    // Very basic mapping, would need expansion for full coverage like pynput
    match key_str.to_lowercase().as_str() {
        "f1" => Ok(Key::F1), "f2" => Ok(Key::F2), "f3" => Ok(Key::F3),
        "f4" => Ok(Key::F4), "f5" => Ok(Key::F5), "f6" => Ok(Key::F6),
        "f7" => Ok(Key::F7), "f8" => Ok(Key::F8), "f9" => Ok(Key::F9),
        "f10" => Ok(Key::F10), "f11" => Ok(Key::F11), "f12" => Ok(Key::F12),
        "enter" | "return" => Ok(Key::Return),
        "tab" => Ok(Key::Tab),
        "space" => Ok(Key::Space),
        "esc" | "escape" => Ok(Key::Escape),
        // ... add mappings for letters, numbers, other keys ...
        "a" => Ok(Key::KeyA), "b" => Ok(Key::KeyB), // ... z
        "0" => Ok(Key::Num0), "1" => Ok(Key::Num1), // ... 9
        _ => Err(anyhow!("Unsupported rdev key string: {}", key_str)),
    }
}


#[cfg(feature = "wayland")]
fn parse_modifier_evdev(mod_str: &str) -> Result<HashSet<u16>> {
    // Use codes from input-event-codes crate or input-linux-sys::KEY_*
    use input_linux_sys::KEY_LEFTCTRL; // Example, import others as needed...
    let codes = match mod_str.to_lowercase().as_str() {
         "ctrl" | "control" => vec![sys::KEY_LEFTCTRL, sys::KEY_RIGHTCTRL],
         "alt" => vec![sys::KEY_LEFTALT, sys::KEY_RIGHTALT],
         "shift" => vec![sys::KEY_LEFTSHIFT, sys::KEY_RIGHTSHIFT],
         "meta" | "super" | "win" | "cmd" | "command" => vec![sys::KEY_LEFTMETA, sys::KEY_RIGHTMETA],
         _ => return Err(anyhow!("Unsupported evdev modifier string: {}", mod_str)),
     };
    Ok(codes.into_iter().collect())
}

#[cfg(feature = "wayland")]
fn parse_key_evdev(key_str: &str) -> Result<u16> {
    match key_str.to_lowercase().as_str() {
         "f1" => Ok(sys::KEY_F1), "f2" => Ok(sys::KEY_F2), //... f12
         "f11" => Ok(sys::KEY_F11),
         "enter" | "return" => Ok(sys::KEY_ENTER),
         "tab" => Ok(sys::KEY_TAB),
         "space" => Ok(sys::KEY_SPACE),
         "esc" | "escape" => Ok(sys::KEY_ESC),
         // ... add mappings for letters, numbers ...
         "a" => Ok(sys::KEY_A), // ... z
         "0" => Ok(sys::KEY_0), // ... 9
         _ => Err(anyhow!("Unsupported evdev key string: {}", key_str)),
     }
}


#[cfg(feature = "wayland")]
fn list_input_devices() -> Result<Vec<PathBuf>> {
    let mut devices = Vec::new();
    for entry in fs::read_dir("/dev/input")? {
        let entry = entry?;
        let path = entry.path();
        if path
            .file_name()
            .map_or(false, |name| name.to_string_lossy().starts_with("event"))
        {
            devices.push(path);
        }
    }
    Ok(devices)
}

#[cfg(feature = "wayland")]
fn open_evdev_device(path: &PathBuf) -> Result<Option<File>> {
    use input_linux::{evdev::EvdevHandle, EventKind, KeyId}; // Need traits/types
    use std::os::unix::fs::OpenOptionsExt; // For custom flags

     // Need read access, non-blocking might be useful later but start with blocking
     // O_NONBLOCK can be added later if using async read or careful poll loops
     let file = OpenOptions::new()
         .read(true)
         // .custom_flags(libc::O_NONBLOCK) // Add if using non-blocking I/O
         .open(path);

    let file = match file {
        Ok(f) => f,
        Err(e) => {
             if e.kind() == io::ErrorKind::PermissionDenied {
                return Err(anyhow!("Permission denied for {}. Run with sudo or add user to 'input' group.", path.display()).context(e));
             } else {
                return Err(anyhow!("Error opening device {}: {}", path.display(), e).context(e));
            }
        }
    };

     // Check if it's a keyboard using ioctl (EVIOCGBIT) - This is more complex
     // Simpler check: Does it report *any* key events? Not perfect.
     // Using the `input-linux` crate's EvdevHandle might simplify this.

     // For now, a basic assumption: if it opens, try reading. Refine later.
     // Proper check requires ioctl calls with EVIOCGBIT to see if EV_KEY is supported
     // and which keys are present. This is low-level C interop.

     // Let's assume if it opens, we'll try and read KEY events.
     // A better implementation would use ioctls here.
     debug!("Opened device: {}", path.display());
    Ok(Some(file))
}


#[cfg(feature = "wayland")]
fn read_evdev_events(file: &mut File, buffer: &mut [u8]) -> io::Result<Vec<InputEvent>> {
    use std::io::Read;
    use input_linux::InputEvent;

     let event_size = size_of::<input_event>();
     let bytes_read = file.read(buffer)?; // Can block if file not opened O_NONBLOCK
                                          // Note: if O_NONBLOCK, can return ErrorKind::WouldBlock

     let num_events = bytes_read / event_size;
     let mut events = Vec::with_capacity(num_events);

     for i in 0..num_events {
         let offset = i * event_size;
         let slice = &buffer[offset..offset + event_size];
         // Unsafe C struct interpretation
         let raw_event: input_event = unsafe { std::ptr::read(slice.as_ptr() as *const _) };
         // Convert to safer Rust struct if possible (or use raw directly)
         if let Some(input_event) = InputEvent::from_raw(&raw_event) {
             events.push(input_event);
         } else {
             warn!("Failed to parse raw evdev event: type={}, code={}, value={}", raw_event.type_, raw_event.code, raw_event.value);
         }
     }
    Ok(events)
}
```

**6. API Interaction (`src/api.rs`)**

```rust
use crate::config::{Config, Service};
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
const REPLICATE_MODEL_VERSION: &str = "3ab86df6c8f54c11309d4d1f930ac292bad43ace52d10c80d87eb258b3c9f79c"; // Whisper v3 large turbo
const REPLICATE_POLL_INTERVAL: Duration = Duration::from_secs(1);
const REPLICATE_POLL_TIMEOUT: Duration = Duration::from_secs(120);

// ElevenLabs constants
const ELEVENLABS_API_URL: &str = "https://api.elevenlabs.io/v1/speech-to-text";
const ELEVENLABS_MODEL: &str = "scribe_v1"; // Or allow configuration


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
    status: String, // "starting", "processing", "succeeded", "failed", "canceled"
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
    debug!("Audio size: {} bytes, Data URI prefix: data:audio/wav;base64,...", audio_bytes.len());


    // 2. Create Prediction
    let create_payload = ReplicateCreatePayload {
        version: REPLICATE_MODEL_VERSION,
        input: ReplicateInput { audio: audio_data_uri, batch_size: 64 },
    };

    let mut prediction_url: Option<String> = None;
    for attempt in 0..=config.retries {
         if attempt > 0 {
            let delay = Duration::from_secs(2u64.pow(attempt -1));
            info!("Retrying Replicate create prediction (attempt {}) after {:?}", attempt + 1, delay);
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
                     info!("Replicate prediction created: ID={}, URL={}", create_resp.id, prediction_url.as_ref().unwrap());
                     break;
                 } else if status == StatusCode::TOO_MANY_REQUESTS || status.is_server_error() {
                     warn!("Replicate create failed ({}), retrying...", status);
                     continue;
                 } else {
                     let error_text = resp.text().await.unwrap_or_else(|_| "Failed to read error body".into());
                     return Err(anyhow!("Replicate create failed ({}): {}", status, error_text));
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
            return Err(anyhow!("Replicate polling timed out after {:?}", REPLICATE_POLL_TIMEOUT));
        }

        info!("Polling Replicate status ({:?} elapsed)...", start_time.elapsed());
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
                             return extract_replicate_transcription(prediction.output)
                        }
                         "failed" => {
                             return Err(anyhow!("Replicate prediction failed: {}", prediction.error.unwrap_or_else(|| "Unknown error".into())));
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
                     let error_text = resp.text().await.unwrap_or_else(|_| "Failed to read error body".into());
                     return Err(anyhow!("Replicate poll failed ({}): {}", status, error_text));
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
                 let combined = segments.iter()
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
         _ => Err(anyhow!("Unexpected or missing output format from Replicate: {:?}", output)),
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
    let file = File::open(audio_path).await
        .context("Failed to open audio file for ElevenLabs upload")?;

    // Stream the file body
    let stream = FramedRead::new(file, BytesCodec::new());
    let file_body = Body::wrap_stream(stream);

    let audio_part = multipart::Part::stream(file_body)
        .file_name(audio_path.file_name().map_or("audio.wav".into(), |n| n.to_string_lossy().into_owned()))
        .mime_str("audio/wav")?;

    let form = multipart::Form::new()
        .text("model_id", ELEVENLABS_MODEL.to_string())
        .part("file", audio_part);

    for attempt in 0..=config.retries {
         if attempt > 0 {
            let delay = Duration::from_secs(2u64.pow(attempt -1));
             info!("Retrying ElevenLabs API call (attempt {}) after {:?}", attempt + 1, delay);
            sleep(delay).await;
             // Need to re-create the form/stream for retry as it's consumed
             let file_retry = File::open(audio_path).await?; // Re-open file
             let stream_retry = FramedRead::new(file_retry, BytesCodec::new());
             let file_body_retry = Body::wrap_stream(stream_retry);
             let audio_part_retry = multipart::Part::stream(file_body_retry).file_name("audio.wav").mime_str("audio/wav")?;
             form = multipart::Form::new().text("model_id", ELEVENLABS_MODEL).part("file", audio_part_retry); // Rebuild form
         }

         // Clone form before sending if retry might happen - reqwest consumes it
         // Alternatively rebuild the form on each retry attempt inside the loop
          let current_form = form.clone(); // Clone necessary parts if form is rebuilt

         let response = client
            .post(ELEVENLABS_API_URL)
            .header("xi-api-key", api_key)
            .multipart(current_form) // Send the potentially rebuilt/cloned form
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
                     let error_text = resp.text().await.unwrap_or_else(|_| "Failed to read error body".into());
                    return Err(anyhow!("ElevenLabs API call failed ({}): {}", status, error_text));
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

    Err(anyhow!("ElevenLabs API call failed after {} retries.", config.retries))
}

```

**7. Output Handling (`src/output.rs`)**

```rust
use crate::config::{Config, OutputType};
use anyhow::{anyhow, Context, Result};
use arboard::Clipboard;
use enigo::{Enigo, Key, KeyboardControllable, Settings};
use log::{debug, info, warn};
use std::path::Path;
use std::process::Command;
use std::thread;
use std::time::Duration;
use tokio::fs::OpenOptions;
use tokio::io::AsyncWriteExt; // for append


pub async fn process_output(config: &Config, text: &str) -> Result<()> {
    if text.is_empty() {
        warn!("Received empty transcription. Skipping output.");
        return Ok(());
    }

    let output_text = text.trim(); // Ensure no leading/trailing whitespace

    match config.output {
        OutputType::Clipboard => {
            write_to_clipboard(output_text)
        }
        OutputType::Paste => {
            direct_type_text(output_text)
        }
        OutputType::File => {
            if let Some(ref path) = config.file {
                 append_to_file(path, output_text).await
            } else {
                 // Already validated in main, but good practice
                 Err(anyhow!("Output type is file, but no output file specified."))
            }
        }
        OutputType::Stdout => {
            info!("\n--- Transcript ---\n{}\n------------------", output_text);
            Ok(())
        }
    }
}

fn write_to_clipboard(text: &str) -> Result<()> {
    let mut clipboard = Clipboard::new().context("Failed to initialize clipboard")?;
    clipboard.set_text(text.to_string())?; // arboard requires String
    info!("Text copied to clipboard.");
    Ok(())
}

async fn append_to_file(path: &Path, text: &str) -> Result<()> {
    let mut file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .await
        .with_context(|| format!("Failed to open or create file for appending: {}", path.display()))?;

    file.write_all(text.as_bytes()).await?;
    file.write_all(b"\n").await?; // Add newline after appending
    info!("Text appended to file: {}", path.display());
    Ok(())
}


// --- Direct Typing / Pasting ---

fn direct_type_text(text: &str) -> Result<()> {
    info!("Attempting to paste/type text: {}...", text.chars().take(50).collect::<String>());

    // 1. Try character-by-character typing first (often more reliable if it works)
    if type_text_char_by_char(text).is_ok() {
         info!("Text output successful (character-by-character).");
         return Ok(());
    } else {
         warn!("Character-by-character typing failed or not supported, falling back to clipboard paste.");
     }

    // 2. Fallback: Copy to clipboard and simulate paste
    write_to_clipboard(text)?;
    thread::sleep(Duration::from_millis(200)); // Give clipboard time

    simulate_paste_command()
}


// --- Character-by-Character Typing (using Enigo primarily) ---
fn type_text_char_by_char(text: &str) -> Result<()> {
    // Enigo can be platform-specific in behavior, especially Wayland
     debug!("Attempting char-by-char typing with Enigo");
     // Workaround for potential Enigo slowness or issues on some platforms
     let mut settings = Settings::default();
     #[cfg(target_os = "linux")]
     {
         // These might help on Linux/Wayland if default is too fast
          settings.linux_delay = Duration::from_micros(10); // Default is 0
     }
     let mut enigo = Enigo::new(&settings)?; // Pass settings

    // Small delay before starting
    thread::sleep(Duration::from_millis(200));

    for c in text.chars() {
        match c {
            '\n' => {
                 enigo.key_click(Key::Return); // Or Key::Enter depending on platform mapping
                 // Add small delay after special keys?
                 // thread::sleep(Duration::from_millis(5));
            }
            '\t' => {
                enigo.key_click(Key::Tab);
                // thread::sleep(Duration::from_millis(5));
            }
            // Handle other potential special characters if needed?
            _ => {
                 // `key_sequence` is generally better than clicking each char
                 // But let's try individual clicks first for simplicity, mimicking Python
                 // enigo.key_click(Key::Layout(c)); // Click based on layout
                 // Safer?:
                 enigo.key_sequence(&c.to_string()); // Types the character sequence
            }
        }
         // Crucial small delay between characters for reliability
         // Adjust delay as needed, start small
          thread::sleep(Duration::from_millis(5)); // 5ms delay
     }

     info!("Enigo character typing sequence finished.");
     Ok(())

    // TODO: Add platform-specific fallbacks if Enigo fails (like the Python script)
    // This would involve checking `cfg!(target_os = "...")` and using `std::process::Command`
    // to call `osascript` (macOS), `wtype` (Wayland), `xdotool` (X11).
     // Example Wayland fallback attempt:
      #[cfg(all(target_os = "linux", feature = "wayland"))]
      {
          if crate::hotkey::is_wayland() && type_text_wtype(text).is_ok() {
               info!("Text typed using wtype (Wayland fallback).");
              return Ok(());
          }
      }
      // Add other fallbacks...

     // If all attempts fail:
     // Err(anyhow!("Character-by-character typing failed on this platform."))
 }

// --- Paste Simulation ---
fn simulate_paste_command() -> Result<()> {
    info!("Simulating paste command (Ctrl+V / Cmd+V).");
    let mut enigo = Enigo::new(&Settings::default())?;

    // Determine modifier based on OS
    let modifier = if cfg!(target_os = "macos") {
        Key::Meta // Command key on macOS
    } else {
         Key::Control // Control key on Windows/Linux
     };

    // Simulate Ctrl/Cmd + V press
    enigo.key_down(modifier)?;
     enigo.key_click(Key::Layout('v')); // Use layout for 'v'
     enigo.key_up(modifier)?;

    info!("Paste command simulated via Enigo.");
    Ok(())

    // TODO: Add platform-specific fallbacks if Enigo paste fails
    // e.g., `osascript -e 'tell application "System Events" to keystroke "v" using command down'`
    // e.g., `xdotool key ctrl+v`
    // e.g., `wl-paste` (less direct simulation, relies on clipboard content) - maybe not needed if clipboard is set.
}


// --- Platform Specific Typing Fallbacks (Example: wtype) ---

#[cfg(all(target_os = "linux", feature = "wayland"))]
fn type_text_wtype(text: &str) -> Result<()> {
    use std::io::Write;

     debug!("Attempting fallback typing with wtype");
     // Check if wtype exists
     if which::which("wtype").is_err() {
         return Err(anyhow!("wtype command not found in PATH."));
     }

     let mut child = Command::new("wtype")
         .arg("-") // Read text from stdin
         .stdin(std::process::Stdio::piped())
         .stdout(std::process::Stdio::null()) // Ignore stdout
         .stderr(std::process::Stdio::piped()) // Capture stderr
         .spawn()
         .context("Failed to spawn wtype process")?;

    // Write text to wtype's stdin
    if let Some(mut stdin) = child.stdin.take() {
        stdin.write_all(text.as_bytes())
            .context("Failed to write text to wtype stdin")?;
        // stdin is dropped here, closing the pipe
    } else {
        return Err(anyhow!("Could not get handle to wtype stdin"));
    }

    // Wait for the process and check status
    let output = child.wait_with_output()
        .context("Failed to wait for wtype process")?;

    if output.status.success() {
        info!("wtype execution successful.");
        Ok(())
    } else {
        let stderr = String::from_utf8_lossy(&output.stderr);
        error!("wtype execution failed. Status: {:?}, Stderr: {}", output.status, stderr);
        Err(anyhow!("wtype command failed: {}", stderr))
    }
}
```

**8. Utility Functions (`src/utils.rs`)**

```rust
use anyhow::{Context, Result};
use directories::ProjectDirs;
use log::debug;
use std::path::PathBuf;
use std::time::{Duration, SystemTime};
use tokio::fs; // Use tokio's async fs

// Get cross-platform cache directory
pub fn get_cache_dir() -> Result<PathBuf> {
    let proj_dirs = ProjectDirs::from("com", "YourAppNameOrOrg", "WhisperDictationRust") // Adjust qualifier, org, app name
        .context("Failed to determine application directories")?;
    Ok(proj_dirs.cache_dir().to_path_buf())
}

// Cleanup old files in a directory
pub async fn cleanup_old_files(dir: &PathBuf, max_age: Duration) -> Result<usize> {
    let mut count = 0;
    let cutoff = SystemTime::now() - max_age;
    debug!("Cleaning up files older than {:?} in {}", cutoff, dir.display());

    let mut entries = fs::read_dir(dir)
        .await
        .with_context(|| format!("Failed to read cache directory: {}", dir.display()))?;

    while let Some(entry) = entries.next_entry().await? {
        let path = entry.path();
        if path.is_file() && path.extension().map_or(false, |ext| ext == "wav") { // Simple check for .wav
             let metadata = fs::metadata(&path).await?;
             if let Ok(modified) = metadata.modified() {
                 if modified < cutoff {
                     debug!("Removing old file: {}", path.display());
                    if let Err(e) = fs::remove_file(&path).await {
                        log::warn!("Failed to remove old file {}: {}", path.display(), e);
                    } else {
                        count += 1;
                    }
                 }
             }
         }
    }
    Ok(count)
}

```

**Key Considerations & Next Steps:**

1.  **Wayland Hotkeys (`input-linux`):** This is the most challenging part.
    *   **Permissions:** Requires running as root or the user being in the `input` group. The code needs to handle `PermissionDenied` errors gracefully and inform the user.
    *   **Device Discovery:** The current `update_devices` logic is basic. A more robust solution would use something like `udev` events if a crate exists, or more frequent polling.
    *   **Keyboard Identification:** The current `open_evdev_device` doesn't properly verify if a device is a keyboard. You need to implement `ioctl` calls (likely via the `ioctl-sys` or similar crate) to check `EVIOCGBIT` for `EV_KEY` and specific key capabilities. The `input-linux` crate's `EvdevHandle` might offer helpers for this – investigate its API.
    *   **Modifier State:** The current modifier state tracking in the Wayland loop is simplistic. A robust solution needs to track the state (`pressed`/`released`) of *each* potential modifier key (Left Ctrl, Right Ctrl, etc.) individually.
    *   **Error Handling:** Needs thorough error handling for file reads, device disconnections etc.
2.  **`rdev` Hotkeys:** The `rdev` implementation needs more robust parsing for modifier/key strings to match the flexibility of the Python version (e.g., handle "cmd", "super" consistently, map more keys). The current listener loop might block indefinitely; investigate if `rdev` offers ways to interrupt it cleanly upon shutdown request (perhaps not easily possible).
3.  **`enigo` Typing/Pasting:** Test thoroughly on X11, Wayland (multiple compositors if possible), macOS, and Windows. Wayland support for `enigo` can be hit-or-miss. Implement the platform-specific fallbacks (`osascript`, `wtype`, `xdotool`) using `std::process::Command` as shown in the `type_text_wtype` example.
4.  **Error Handling:** Implement more specific error types using `thiserror` or ensure `anyhow` contexts are descriptive. Handle potential panics (e.g., `Mutex` poisoning, though less likely with careful locking).
5.  **Dependencies:** Ensure necessary system libraries are installed (e.g., `libasound2-dev` on Debian/Ubuntu for `cpal`, potentially X11 dev libs for `rdev` or `enigo` backends).
6.  **Compilation:** Use `cargo build --features wayland` on Linux if you need the Wayland hotkey listener.
7.  **API Models:** Allow configuring the specific Whisper model versions for Replicate/ElevenLabs via command-line arguments or config files.
8.  **Refinement:** The code needs more testing, logging improvements, and potential refactoring for clarity (e.g., breaking down large functions). The audio callback could potentially signal the main loop via a channel when max duration is hit, rather than just setting a flag.

This comprehensive structure provides a solid starting point for the Rust translation. The Wayland hotkey part remains the most significant hurdle requiring low-level system interaction. Remember to test incrementally!
