use crate::config::{Config, OutputType};
use anyhow::{anyhow, Context, Result};
use arboard::Clipboard;
use enigo::{Enigo, Key, Keyboard, Settings};
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

    enigo.text(text);

     info!("Enigo character typing sequence finished.");
     Ok(())

         /*
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
     // */
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
    enigo.key(modifier, enigo::Direction::Press)?;
    enigo.key(Key::Unicode('v'), enigo::Direction::Click)?;
    enigo.key(modifier, enigo::Direction::Release)?;

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
