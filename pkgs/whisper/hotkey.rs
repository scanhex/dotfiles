use crate::config::Config;
use anyhow::{anyhow, Result};
use log::{debug, error, info, warn};
use rdev::{listen, Event, EventType, Key};
// Use std mpsc for sync listener thread
use crate::utils::is_wayland;
use std::sync::{Arc, Mutex};
use tokio::sync::mpsc::Sender; // Use tokio mpsc for sending to async main loop

#[cfg(feature = "wayland")]
use evdev::{Device, KeyCode};

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
            anyhow::bail!("Wayland detected, but the 'wayland' feature is not enabled in this build. Recompile with --features wayland.")
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

    struct State {
        mod_pressed: bool,
        key_pressed: bool,
    }

    let state = Arc::new(Mutex::new(State {
        mod_pressed: false,
        key_pressed: false,
    }));

    let (async_tx, mut async_rx) = tokio::sync::mpsc::unbounded_channel::<HotkeyEvent>();

    // Bridge from std::sync::mpsc to tokio::sync::mpsc
    let bridge_tx = tx.clone();
    tokio::spawn(async move {
        while let Some(event) = async_rx.recv().await {
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

    while crate::IS_RUNNING.load(std::sync::atomic::Ordering::Relaxed) {
        let state_copy = state.clone();
        let async_tx_copy = async_tx.clone();
        let callback = move |event: Event| {
            match event.event_type {
                EventType::KeyPress(key) => {
                    let mut state_val = state_copy.lock().unwrap();
                    // Check modifier press
                    if key == target_modifier.0 || key == target_modifier.1 {
                        state_val.mod_pressed = true;
                        state_val.key_pressed = false;
                        // Reset key pressed state if modifier is re-pressed
                        debug!("rdev: Modifier {:?} pressed", key);
                    }
                    // Check target key press ONLY if modifier is ALREADY held
                    else if key == target_key {
                        // Only trigger if main key wasn't already down AND modifier is down
                        if !state_val.key_pressed && state_val.mod_pressed {
                            debug!("rdev: Target key {:?} pressed with modifier held", key);
                            // Send toggle event
                            if async_tx_copy.send(HotkeyEvent::ToggleRecording).is_err() {
                                error!("rdev: Failed to send toggle event from callback.");
                                // Consider how to signal failure or stop listening
                            }
                            state_val.key_pressed = true;
                        } else if state_val.key_pressed {
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
                    let mut state_val = state_copy.lock().unwrap();
                    // Check modifier release
                    if key == target_modifier.0 || key == target_modifier.1 {
                        state_val.mod_pressed = false;
                        state_val.key_pressed = false;
                        debug!("rdev: Modifier {:?} released", key);
                    }
                    // Check target key release
                    else if key == target_key {
                        state_val.key_pressed = false;
                        debug!("rdev: Target key {:?} released", key);
                    } else {
                        // Other key released
                    }
                }
                _ => (), // Ignore mouse/other events
            }
        };
        if let Err(e) = listen(callback) {
            error!("rdev error: {:?}", e);
        }
    }

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
    use evdev::{EventType, KeyCode};
    use std::collections::{HashMap, HashSet};

    // Keys we care about ------------------------------------------------------
    let target_mods = parse_modifier_evdev(&config.modifier)?;
    let target_key = parse_key_evdev(&config.key)?;

    info!("evdev: listening for mods={target_mods:?}, key={target_key:?}");

    // One lightweight runtime -------------------------------------------------
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_io()
        .build()?;

    rt.block_on(async move {
        // Discover keyboards once at start; we’ll refresh on udev events later.
        let mut devices = HashMap::new();
        if let Err(e) = scan_keyboards(&mut devices) {
            error!("Failed to scan keyboards: {}", e);
            return;
        }

        // Channel every device will write into
        let (evt_tx, mut evt_rx) = tokio::sync::mpsc::unbounded_channel::<evdev::InputEvent>();

        // Spawn one async task per device
        for dev in devices.into_values() {
            let stream = match dev.into_event_stream() {
                Ok(s) => s,
                Err(e) => {
                    error!("Failed to create event stream: {}", e);
                    continue;
                }
            };
            let mut stream = stream;
            let evt_tx = evt_tx.clone();
            tokio::spawn(async move {
                loop {
                    match stream.next_event().await {
                        Ok(ev) => {
                            if evt_tx.send(ev).is_err() {
                                break;
                            }
                        }
                        Err(e) => {
                            error!("evdev: stream error: {e}");
                            break;
                        }
                    }
                }
            });
        }
        drop(evt_tx); // closes when all senders gone

        // Modifier bookkeeping ------------------------------------------------
        let mut pressed_keys: HashSet<KeyCode> = HashSet::new();

        while let Some(ev) = evt_rx.recv().await {
            // Only care about key events
            if ev.event_type() != EventType::KEY {
                continue;
            }
            let key: KeyCode = KeyCode::new(ev.code());
            let pressed = ev.value() != 0;

            if pressed {
                pressed_keys.insert(key);
            } else {
                pressed_keys.remove(&key);
            }
            if key == target_key
                && pressed
                && (pressed_keys.contains(&target_mods.0) || pressed_keys.contains(&target_mods.1))
            {
                if let Err(e) = tx.send(HotkeyEvent::ToggleRecording).await {
                    warn!("evdev: Hotkey receiver dropped – stopping listener: {}", e);
                    break;
                }
            }
        }
    });

    info!("evdev listener finished");
    Ok(())
}

// --- Helper Functions ---

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
        "f1" => Ok(Key::F1),
        "f2" => Ok(Key::F2),
        "f3" => Ok(Key::F3),
        "f4" => Ok(Key::F4),
        "f5" => Ok(Key::F5),
        "f6" => Ok(Key::F6),
        "f7" => Ok(Key::F7),
        "f8" => Ok(Key::F8),
        "f9" => Ok(Key::F9),
        "f10" => Ok(Key::F10),
        "f11" => Ok(Key::F11),
        "f12" => Ok(Key::F12),
        "enter" | "return" => Ok(Key::Return),
        "tab" => Ok(Key::Tab),
        "space" => Ok(Key::Space),
        "esc" | "escape" => Ok(Key::Escape),
        // ... add mappings for letters, numbers, other keys ...
        "a" => Ok(Key::KeyA),
        "b" => Ok(Key::KeyB), // ... z
        "0" => Ok(Key::Num0),
        "1" => Ok(Key::Num1), // ... 9
        _ => Err(anyhow!("Unsupported rdev key string: {}", key_str)),
    }
}

#[cfg(feature = "wayland")]
fn parse_modifier_evdev(mod_str: &str) -> Result<(KeyCode, KeyCode)> {
    use evdev::KeyCode;
    let codes = match mod_str.to_lowercase().as_str() {
        "ctrl" | "control" => (KeyCode::KEY_LEFTCTRL, KeyCode::KEY_RIGHTCTRL),
        "alt" => (KeyCode::KEY_LEFTALT, KeyCode::KEY_RIGHTALT),
        "shift" => (KeyCode::KEY_LEFTSHIFT, KeyCode::KEY_RIGHTSHIFT),
        "meta" | "super" | "win" | "cmd" | "command" => {
            (KeyCode::KEY_LEFTMETA, KeyCode::KEY_RIGHTMETA)
        }
        _ => return Err(anyhow!("Unsupported evdev modifier string: {}", mod_str)),
    };
    Ok(codes)
}

#[cfg(feature = "wayland")]
fn parse_key_evdev(key_str: &str) -> Result<KeyCode> {
    use evdev::KeyCode;
    match key_str.to_lowercase().as_str() {
        "f1" => Ok(KeyCode::KEY_F1),
        "f2" => Ok(KeyCode::KEY_F2),
        "f3" => Ok(KeyCode::KEY_F3),
        "f4" => Ok(KeyCode::KEY_F4),
        "f5" => Ok(KeyCode::KEY_F5),
        "f6" => Ok(KeyCode::KEY_F6),
        "f7" => Ok(KeyCode::KEY_F7),
        "f8" => Ok(KeyCode::KEY_F8),
        "f9" => Ok(KeyCode::KEY_F9),
        "f10" => Ok(KeyCode::KEY_F10),
        "f11" => Ok(KeyCode::KEY_F11),
        "f12" => Ok(KeyCode::KEY_F12),
        "enter" | "return" => Ok(KeyCode::KEY_ENTER),
        "tab" => Ok(KeyCode::KEY_TAB),
        "space" => Ok(KeyCode::KEY_SPACE),
        "esc" | "escape" => Ok(KeyCode::KEY_ESC),
        "a" => Ok(KeyCode::KEY_A),
        "b" => Ok(KeyCode::KEY_B),
        "0" => Ok(KeyCode::KEY_0),
        "1" => Ok(KeyCode::KEY_1),
        _ => Err(anyhow!("Unsupported evdev key string: {}", key_str)),
    }
}

#[cfg(feature = "wayland")]
use std::collections::HashMap;
#[cfg(feature = "wayland")]
use std::path::PathBuf;
#[cfg(feature = "wayland")]
fn scan_keyboards(devices: &mut HashMap<PathBuf, Device>) -> Result<()> {
    use evdev::{enumerate, Device, EventType, KeyCode};
    use std::collections::HashSet;

    // Get current device paths
    let current_paths: HashSet<PathBuf> = enumerate().map(|(path, _)| path).collect();

    debug!("evdev: Found {} total input devices", current_paths.len());

    let known_paths: HashSet<PathBuf> = devices.keys().cloned().collect();

    // Remove disconnected devices
    for path in known_paths.difference(&current_paths) {
        info!("evdev: Device disconnected: {}", path.display());
        devices.remove(path);
    }

    // Add new keyboard devices
    for path in current_paths.difference(&known_paths) {
        debug!("evdev: Checking device: {}", path.display());
        if let Ok(device) = Device::open(&path) {
            // Check if it's a keyboard by looking for key events and typical keyboard keys
            if device.supported_events().contains(EventType::KEY) {
                let keys = device
                    .supported_keys()
                    .map(|keys| keys.into_iter().collect::<Vec<_>>())
                    .unwrap_or_default();

                // Check for typical keyboard keys
                let has_keyboard_keys = keys.iter().any(|&key| {
                    matches!(
                        key,
                        KeyCode::KEY_A
                            | KeyCode::KEY_B
                            | KeyCode::KEY_C
                            | KeyCode::KEY_SPACE
                            | KeyCode::KEY_ENTER
                            | KeyCode::KEY_LEFTSHIFT
                            | KeyCode::KEY_LEFTCTRL
                    )
                });

                if has_keyboard_keys {
                    info!(
                        "evdev: Added keyboard device: {} ({}) with {} keys",
                        path.display(),
                        device.name().unwrap_or("Unknown"),
                        keys.len()
                    );
                    devices.insert(path.clone(), device);
                } else {
                    debug!(
                        "evdev: Device {} has KEY events but no keyboard keys",
                        path.display()
                    );
                }
            } else {
                debug!(
                    "evdev: Device {} does not support KEY events",
                    path.display()
                );
            }
        } else {
            debug!(
                "evdev: Cannot open device {}, likely permission issue",
                path.display()
            );
        }
    }

    Ok(())
}
