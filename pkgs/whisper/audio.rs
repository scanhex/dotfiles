use anyhow::{anyhow, Context, Result};
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{SampleRate, Stream, StreamConfig, SupportedStreamConfigRange};
use hound::{SampleFormat as HoundSampleFormat, WavSpec, WavWriter};
use log::{debug, info, warn};
use std::path::Path;
use std::sync::{Arc, Mutex};
use std::time::Duration;

pub const MAX_SAMPLE_RATE: u32 = 44100;
pub const MAX_CHANNELS: u16 = 2;

pub struct AudioRecorder {
    // Store frames in an Arc<Mutex> to allow access from audio callback thread
    frames: Arc<Mutex<Vec<f32>>>,
    stream: Option<Stream>, // Keep the stream alive
    stream_config: Option<StreamConfig>,
    max_duration: Duration,
    max_frames: usize,
    is_recording_flag: Arc<Mutex<bool>>, // Flag to signal recording state
}

impl AudioRecorder {
    pub fn new(max_time_seconds: u32) -> Result<Self> {
        let max_duration = Duration::from_secs(max_time_seconds as u64);
        let max_frames = (MAX_SAMPLE_RATE * MAX_CHANNELS as u32 * max_time_seconds) as usize;
        info!(
            "Audio Recorder configured: max {} Hz, max {} channels, Max Duration: {:?}, Max Frames: {}",
            MAX_SAMPLE_RATE, MAX_CHANNELS, max_duration, max_frames
        );

        Ok(Self {
            frames: Arc::new(Mutex::new(Vec::with_capacity(max_frames))),
            stream: None,
            stream_config: None,
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

        // Check if format is supported
        let supported_configs: Vec<SupportedStreamConfigRange> =
            device.supported_input_configs()?.collect();
        info!("Supported input formats:");
        for config in &supported_configs {
            info!(
                "  - {} channels, {} Hz, {:?}",
                config.channels(),
                config.min_sample_rate().0,
                config.sample_format()
            );
        }
        let supported = supported_configs
            .iter()
            .filter(|c| c.channels() <= MAX_CHANNELS && c.min_sample_rate().0 <= MAX_SAMPLE_RATE)
            .max_by_key(|c| (c.channels(), c.max_sample_rate().0))
            .ok_or_else(|| anyhow!("No supported audio configurations found"))?;

        let config = StreamConfig {
            channels: supported.channels(),
            sample_rate: SampleRate(std::cmp::min(
                supported.max_sample_rate().0,
                MAX_SAMPLE_RATE,
            )),
            buffer_size: cpal::BufferSize::Default,
        };

        info!(
            "Using audio format: {}Hz, {}ch, {:?}",
            config.sample_rate.0,
            config.channels,
            supported.sample_format()
        );
        info!("Device supports the required audio format.");

        let shared_frames = self.frames.clone();
        let max_frames = self.max_frames;
        let is_recording_flag_callback = self.is_recording_flag.clone();
        let stop_recording_flag_callback = self.is_recording_flag.clone(); // Need to access it to stop

        let err_fn = |err| panic!("An error occurred on the audio stream: {}", err);

        let stream = device.build_input_stream(
            &config,
            move |data: &[f32], _: &cpal::InputCallbackInfo| {
                // Check if we should still be recording
                if !is_recording_flag_callback
                    .lock()
                    .expect("Mutex poisoned")
                    .clone()
                {
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

        self.stream_config = Some(config);

        stream.play()?;
        self.stream = Some(stream);
        *self.is_recording_flag.lock().expect("Mutex poisoned") = true;
        info!("Audio recording started.");

        Ok(())
    }

    pub fn stop(&mut self) -> Result<Option<(StreamConfig, Vec<f32>)>> {
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
        } else if self.stream_config.is_none() {
            Err(anyhow!("No stream config - start() was supposed to fill it"))
        } else {
            Ok(Some((self.stream_config.clone().unwrap(), frames.clone()))) 
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
    debug!(
        "Successfully saved {} samples to {}",
        data.len(),
        path.display()
    );
    Ok(())
}
