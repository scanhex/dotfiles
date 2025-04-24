// whisper_dictation_rs/src/main.rs
// A lightweight dictation tool similar to the Python Whisper‑Dictation script
// - Global hotkey (rdev, evdev on Wayland)
// - Records microphone (cpal) and writes temporary WAV (hound)
// - Sends to ElevenLabs or Replicate for STT (reqwest)
// - Outputs via clipboard, simulated typing (enigo), file, or stdout
// Built for Rust 1.77+

use anyhow::{anyhow, Context, Result};
use arboard::Clipboard;
use clap::{ArgEnum, Parser, ValueEnum};
use crossbeam_channel::{bounded, select};
use enigo::{Enigo, Key, KeyboardControllable};
use once_cell::sync::Lazy;
use rdev::{listen, Event, EventType, Key as RKey};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tempfile::NamedTempFile;
use tokio::runtime::Runtime;
use base64::base64;

// -------- Command‑line interface --------
#[derive(Parser, Debug)]
#[command(author, version, about)]
struct Cli {
    /// API key or token for the chosen service
    #[arg(short = 'k', long)]
    api_key: Option<String>,

    /// Service to use for speech‑to‑text
    #[arg(value_enum, long, default_value_t = Service::ElevenLabs)]
    service: Service,

    /// Output destination
    #[arg(value_enum, long, default_value_t = OutputMode::Clipboard)]
    output: OutputMode,

    /// File path if output = file
    #[arg(short, long)]
    file: Option<PathBuf>,

    /// Modifier key for the hotkey (ctrl | alt | shift | meta | cmd)
    #[arg(long, default_value = "ctrl")]
    modifier: String,

    /// Main key for the hotkey (e.g. f11, a, space)
    #[arg(long, default_value = "f11")]
    key: String,

    /// Maximum recording time in seconds
    #[arg(long, default_value_t = 60)]
    max_time: u32,
}

#[derive(Copy, Clone, Debug, ValueEnum)]
enum Service {
    Replicate,
    ElevenLabs,
}

#[derive(Copy, Clone, Debug, ValueEnum)]
enum OutputMode {
    Clipboard,
    Paste,
    File,
    Stdout,
}

// -------- Global runtime flags --------
static IS_RECORDING: AtomicBool = AtomicBool::new(false);
static SHOULD_EXIT: AtomicBool = AtomicBool::new(false);

// Ugly static but fine for small tool
static RECORDER: Lazy<Mutex<Option<Recorder>>> = Lazy::new(|| Mutex::new(None));

// -------- Audio recording (cpal + hound) --------
struct Recorder {
    sample_rate: u32,
    channels: u16,
    max_secs: u32,
    frames: Vec<i16>,
}

impl Recorder {
    fn new(sample_rate: u32, channels: u16, max_secs: u32) -> Self {
        Self { sample_rate, channels, max_secs, frames: Vec::new() }
    }

    fn start(&mut self) -> Result<()> {
        use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
        let host = cpal::default_host();
        let device = host
            .default_input_device()
            .ok_or_else(|| anyhow!("No input device available"))?;
        let mut supported = device.supported_input_configs()?;
        let cfg = supported.find(|c| c.sample_format() == cpal::SampleFormat::I16).ok_or_else(|| anyhow!("No i16 input format"))?;
        let fmt = cfg.with_max_sample_rate().config();
        if fmt.channels != self.channels {
            eprintln!("Warning: device has {} channels, using {}");
        }
        let max_samples = self.sample_rate as usize * self.max_secs as usize * self.channels as usize;
        let frames = Arc::new(Mutex::new(Vec::<i16>::with_capacity(max_samples)));
        let frames_clone = frames.clone();
        let stream = device.build_input_stream(&fmt, move |data: &[i16], _: &cpal::InputCallbackInfo| {
            let mut guard = frames_clone.lock().unwrap();
            guard.extend_from_slice(data);
        }, move |err| {
            eprintln!("Stream error: {err}");
        }, None)?;
        stream.play()?;
        // Busy‑wait until IS_RECORDING flips false or buffer full
        let start = Instant::now();
        while IS_RECORDING.load(Ordering::SeqCst) {
            if start.elapsed().as_secs() >= self.max_secs as u64 { break; }
            std::thread::sleep(Duration::from_millis(50));
        }
        drop(stream);
        self.frames = Arc::try_unwrap(frames).unwrap().into_inner().unwrap();
        Ok(())
    }

    fn write_wav(&self, path: &Path) -> Result<()> {
        let spec = hound::WavSpec { channels: self.channels, sample_rate: self.sample_rate, bits_per_sample: 16, sample_format: hound::SampleFormat::Int };
        let mut writer = hound::WavWriter::create(path, spec)?;
        for &s in &self.frames { writer.write_sample(s)?; }
        writer.finalize()?;
        Ok(())
    }
}

// -------- Hotkey listeners --------
fn start_hotkey_listener(modifier: String, key: String, toggle_tx: crossbeam_channel::Sender<()>) {
    // Detect Wayland
    let is_wayland = std::env::var("WAYLAND_DISPLAY").is_ok();
    if is_wayland {
        std::thread::spawn(move || wayland_evdev_listener(modifier, key, toggle_tx));
    } else {
        std::thread::spawn(move || rdev_listener(modifier, key, toggle_tx));
    }
}

fn rdev_listener(modifier: String, key: String, toggle_tx: crossbeam_channel::Sender<()>) {
    let (mod_matcher, key_matcher) = build_rdev_matchers(&modifier, &key);
    let callback = move |event: Event| {
        match event.event_type {
            EventType::KeyPress(k) => {
                if key_matcher(k) {
                    // Need current modifiers, but rdev API limited; simple check using event.modifiers
                    if let Some(m) = event.modifiers { if mod_matcher(m) { let _ = toggle_tx.send(()); } }
                }
            }
            _ => {}
        }
    };
    listen(callback).expect("rdev listener failed");
}

fn build_rdev_matchers(mod_str: &str, key_str: &str) -> (impl Fn(rdev::Modifiers) -> bool + Send + 'static, impl Fn(RKey) -> bool + Send + 'static) {
    let mod_flag = match mod_str { "ctrl" => rdev::ModiferType::CONTROL, "alt" => rdev::ModiferType::ALT, "shift" => rdev::ModiferType::SHIFT, _ => rdev::ModiferType::META };
    let key_matcher = parse_key(key_str);
    let mod_fn = move |mods: rdev::Modifiers| mods.contains(mod_flag);
    (mod_fn, key_matcher)
}

fn parse_key(s: &str) -> impl Fn(RKey) -> bool + Send + 'static {
    let lower = s.to_lowercase();
    match lower.as_str() {
        "f1" => |k| k == RKey::F1,
        "f2" => |k| k == RKey::F2,
        "f3" => |k| k == RKey::F3,
        "f4" => |k| k == RKey::F4,
        "f5" => |k| k == RKey::F5,
        "f6" => |k| k == RKey::F6,
        "f7" => |k| k == RKey::F7,
        "f8" => |k| k == RKey::F8,
        "f9" => |k| k == RKey::F9,
        "f10" => |k| k == RKey::F10,
        "f11" => |k| k == RKey::F11,
        "f12" => |k| k == RKey::F12,
        _ if lower.len() == 1 => {
            let c = lower.chars().next().unwrap();
            move |k| matches!(k, RKey::Key(ch) if ch.to_ascii_lowercase() == c)
        }
        _ => |_| false,
    }
}

fn wayland_evdev_listener(modifier: String, key: String, toggle_tx: crossbeam_channel::Sender<()>) {
    use evdev::{Device, InputEventKind, Key as EKey};
    // Map strings to evdev codes
    let mods = match modifier.as_str() {
        "ctrl" => vec![EKey::LEFTCTRL, EKey::RIGHTCTRL],
        "alt" => vec![EKey::LEFTALT, EKey::RIGHTALT],
        "shift" => vec![EKey::LEFTSHIFT, EKey::RIGHTSHIFT],
        _ => vec![EKey::LEFTMETA, EKey::RIGHTMETA],
    };
    let main_code = str_to_evdev(&key).unwrap_or(EKey::F11);
    // Open all keyboards
    let mut fds: Vec<Device> = evdev::enumerate().filter_map(|(_, d)| if d.supported_keys().map(|k| k.contains(EKey::KEY_A)).unwrap_or(false) { Some(d) } else { None }).collect();
    loop {
        for dev in &mut fds {
            if let Ok(events) = dev.fetch_events() {
                for ev in events {
                    if let InputEventKind::Key(code) = ev.kind() {
                        let down = ev.value() == 1;
                        if down && code == main_code {
                            // Check modifier state via device states (best‑effort)
                            if mods.iter().any(|m| dev.state().key_vals().unwrap_or(&[]) .iter().any(|(k, v)| k == m && *v)) {
                                let _ = toggle_tx.send(());
                            }
                        }
                    }
                }
            }
        }
        if SHOULD_EXIT.load(Ordering::SeqCst) { break; }
        std::thread::sleep(Duration::from_millis(20));
    }
}

fn str_to_evdev(k: &str) -> Option<evdev::Key> {
    use evdev::Key as K;
    Some(match k.to_lowercase().as_str() {
        "f1" => K::KEY_F1,
        "f2" => K::KEY_F2,
        "f3" => K::KEY_F3,
        "f4" => K::KEY_F4,
        "f5" => K::KEY_F5,
        "f6" => K::KEY_F6,
        "f7" => K::KEY_F7,
        "f8" => K::KEY_F8,
        "f9" => K::KEY_F9,
        "f10" => K::KEY_F10,
        "f11" => K::KEY_F11,
        "f12" => K::KEY_F12,
        c if c.len() == 1 && c.chars().all(|ch| ch.is_ascii_alphanumeric()) => {
            let ch = c.chars().next().unwrap().to_ascii_uppercase();
            unsafe { std::mem::transmute::<u8, K>(ch as u8 - b'A' + 30) } // crude A=KEY_A (30)
        }
        _ => return None,
    })
}

// -------- STT API interaction --------
fn transcribe(service: Service, api_key: &str, wav_path: &Path) -> Result<String> {
    match service {
        Service::ElevenLabs => elevenlabs_request(api_key, wav_path),
        Service::Replicate => replicate_request(api_key, wav_path),
    }
}

fn elevenlabs_request(api_key: &str, wav: &Path) -> Result<String> {
    #[derive(Deserialize)]
    struct Response { text: String }
    let client = reqwest::blocking::Client::new();
    let resp: Response = client
        .post("https://api.elevenlabs.io/v1/speech-to-text")
        .header("xi-api-key", api_key)
        .form(&HashMap::from([("model_id", "scribe_v1")]))
        .send()?
        .error_for_status()?
        .json()?;
    Ok(resp.text.trim().to_string())
}

fn replicate_request(api_key: &str, wav: &Path) -> Result<String> {
    #[derive(Serialize)]
    struct Input { audio: String, batch_size: u8 }
    #[derive(Serialize)]
    struct CreateReq { version: String, input: Input }
    #[derive(Deserialize)]
    struct CreateResp { id: String, urls: Urls }
    #[derive(Deserialize)]
    struct Urls { get: String }
    #[derive(Deserialize)]
    struct PollResp { status: String, output: Option<serde_json::Value>, error: Option<String> }

    let b64 = fs::read(wav).map(|d| base64::encode(d))?;
    let payload = CreateReq { version: "3ab86df6c8f54c11309d4d1f930ac292bad43ace52d10c80d87eb258b3c9f79c".into(), input: Input { audio: format!("data:audio/wav;base64,{b64}"), batch_size: 64 } };
    let client = reqwest::blocking::Client::new();
    let create: CreateResp = client.post("https://api.replicate.com/v1/predictions")
        .bearer_auth(api_key)
        .json(&payload).send()?.error_for_status()?.json()?;
    // poll
    let start = Instant::now();
    loop {
        let poll: PollResp = client.get(&create.urls.get).bearer_auth(api_key).send()?.error_for_status()?.json()?;
        match poll.status.as_str() {
            "succeeded" => {
                if let Some(out) = poll.output {
                    if let Some(text) = out.get("transcription").or_else(|| out.get("text")).and_then(|v| v.as_str()) { return Ok(text.trim().into()); }
                }
                return Err(anyhow!("No transcription in output"));
            }
            "failed" => return Err(anyhow!(poll.error.unwrap_or_else(|| "Replicate failed".into()))),
            _ => {
                if start.elapsed() > Duration::from_secs(120) { return Err(anyhow!("Timeout")); }
                std::thread::sleep(Duration::from_secs(1));
            }
        }
    }
}

// -------- Output helpers --------
fn output_text(mode: OutputMode, text: &str, file_path: &Option<PathBuf>) -> Result<()> {
    match mode {
        OutputMode::Clipboard => {
            Clipboard::new()?.set_text(text.to_string())?;
            eprintln!("Copied to clipboard");
        }
        OutputMode::Stdout => println!("{text}"),
        OutputMode::File => {
            let path = file_path.as_ref().ok_or_else(|| anyhow!("--file required"))?;
            let mut f = fs::OpenOptions::new().create(true).append(true).open(path)?;
            writeln!(f, "{text}")?;
        }
        OutputMode::Paste => {
            // attempt typing, else clipboard+paste
            if !type_char_by_char(text) {
                Clipboard::new()?.set_text(text.to_string())?;
                paste_shortcut()?;
            }
        }
    }
    Ok(())
}

fn type_char_by_char(s: &str) -> bool {
    let mut enigo = Enigo::new();
    // heuristic: best effort; skip if too long (>500) to avoid delay
    if s.len() > 500 { return false; }
    for ch in s.chars() {
        match ch {
            '\n' => { enigo.key_click(Key::Return); },
            '\t' => { enigo.key_click(Key::Tab); },
            _ => enigo.key_sequence(&ch.to_string()),
        }
    }
    true
}

fn paste_shortcut() -> Result<()> {
    let mut enigo = Enigo::new();
    if cfg!(target_os = "macos") {
        enigo.key_down(Key::Meta);
        enigo.key_click(Key::Layout('v'));
        enigo.key_up(Key::Meta);
    } else {
        enigo.key_down(Key::Control);
        enigo.key_click(Key::Layout('v'));
        enigo.key_up(Key::Control);
    }
    Ok(())
}

// -------- Main orchestration --------
fn main() -> Result<()> {
    let cli = Cli::parse();
    let api_key = cli.api_key.or_else(|| std::env::var(match cli.service { Service::Replicate => "REPLICATE_API_TOKEN", Service::ElevenLabs => "ELEVENLABS_API_KEY" }).ok()).context("API key required")?;

    // Channels for hotkey toggle
    let (tx, rx) = bounded::<()>(1);
    start_hotkey_listener(cli.modifier.clone(), cli.key.clone(), tx);

    eprintln!("Whisper dictation ready. Press {}+{} to toggle.", cli.modifier, cli.key);

    loop {
        select! {
            recv(rx) -> _ => {
                if IS_RECORDING.swap(!IS_RECORDING.load(Ordering::SeqCst), Ordering::SeqCst) {
                    // stop recording
                    SHOULD_EXIT.store(false, Ordering::SeqCst);
                } else {
                    // start recording
                    let mut rec = Recorder::new(16_000, 1, cli.max_time);
                    IS_RECORDING.store(true, Ordering::SeqCst);
                    rec.start()?;
                    IS_RECORDING.store(false, Ordering::SeqCst);
                    let mut wav = NamedTempFile::new()?;
                    rec.write_wav(wav.path())?;
                    let text = transcribe(cli.service, &api_key, wav.path())?;
                    output_text(cli.output, &text, &cli.file)?;
                }
            },
            default(Duration::from_millis(100)) => if SHOULD_EXIT.load(Ordering::SeqCst) { break; },
        }
    }
    Ok(())
}

