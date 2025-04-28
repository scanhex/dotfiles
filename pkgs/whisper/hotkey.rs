use crate::config::Config;
use anyhow::{anyhow, bail, Context, Result};
use log::{debug, error, info, warn};
use rdev::{listen, Event, EventType, Key, KeyboardState, ListenError};
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
    use input_linux::{
        sys::{input_event, timeval}, // Use raw C structs
        EventKind,
        EventTime,
        InputEvent,
        InputId,
        KeyId, // Use abstractions when possible
        KeyState,
    };
    use input_linux_sys as sys; // Alias for ecodes
    use libc::{nfds_t, poll, pollfd, POLLIN};
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
        let mut update_devices =
            |devices: &mut HashMap<PathBuf, File>, poll_fds: &mut Vec<pollfd>| -> Result<()> {
                let current_device_paths: HashSet<PathBuf> = list_input_devices()?
                    .into_iter()
                    .filter(|p| {
                        p.file_name()
                            .map_or(false, |n| n.to_string_lossy().starts_with("event"))
                    })
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
                if err.kind() == io::ErrorKind::Interrupted {
                    continue;
                } // Interrupted by signal, safe to retry
                error!("evdev: poll error: {}", err);
                thread::sleep(Duration::from_secs(1)); // Avoid spamming errors
                continue;
            }

            if num_events == 0 {
                continue;
            } // Timeout, no events

            // Process events from ready file descriptors
            let mut device_to_remove: Option<PathBuf> = None;
            for pfd in &poll_fds {
                if pfd.revents & POLLIN != 0 {
                    let path = devices
                        .iter()
                        .find(|(_, file)| file.as_raw_fd() == pfd.fd)
                        .map(|(p, _)| p.clone()); // Find path by fd

                    if let Some(p) = path.as_ref() {
                        let device_file = devices.get_mut(p).unwrap(); // Should exist

                        match read_evdev_events(device_file, &mut buffer) {
                            Ok(events) => {
                                for event in events {
                                    if !crate::IS_RUNNING.load(std::sync::atomic::Ordering::Relaxed)
                                    {
                                        return Ok(());
                                    }

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
                                                debug!(
                                                    "evdev: Modifier {:?} pressed/repeat",
                                                    key_code
                                                );
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
                                                if std_tx
                                                    .send(HotkeyEvent::ToggleRecording)
                                                    .is_err()
                                                {
                                                    error!("evdev: Failed to send toggle event.");
                                                    // Consider how to handle this channel break
                                                    return Err(anyhow!(
                                                        "Failed to send to main thread"
                                                    ));
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
                                if e.kind() == io::ErrorKind::WouldBlock
                                    || e.kind() == io::ErrorKind::Interrupted
                                {
                                    continue; // Not really errors in non-blocking read
                                } else if e.kind() == io::ErrorKind::NotConnected
                                    || e.kind() == io::ErrorKind::NotFound
                                {
                                    // Device likely unplugged
                                    warn!(
                                        "evdev: Device {} disconnected or error: {}",
                                        p.display(),
                                        e
                                    );
                                    device_to_remove = Some(p.clone());
                                } else {
                                    error!("evdev: Error reading from {}: {}", p.display(), e);
                                    device_to_remove = Some(p.clone());
                                }
                            }
                        }
                    }
                } // End processing ready descriptor
            }

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
            if !crate::IS_RUNNING.load(std::sync::atomic::Ordering::Relaxed) {
                break;
            }
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
        "f1" => Ok(sys::KEY_F1),
        "f2" => Ok(sys::KEY_F2), //... f12
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
                return Err(anyhow!(
                    "Permission denied for {}. Run with sudo or add user to 'input' group.",
                    path.display()
                )
                .context(e));
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
    use input_linux::InputEvent;
    use std::io::Read;

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
            warn!(
                "Failed to parse raw evdev event: type={}, code={}, value={}",
                raw_event.type_, raw_event.code, raw_event.value
            );
        }
    }
    Ok(events)
}
