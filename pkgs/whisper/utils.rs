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
