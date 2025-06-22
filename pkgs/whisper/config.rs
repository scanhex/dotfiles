use clap::{Parser, ValueEnum};
use std::path::PathBuf;

#[derive(Parser, Debug, Clone)]
#[command(
    author,
    version,
    about = "Whisper Dictation (Rust) - Dictate and paste via APIs"
)]
pub struct Config {
    /// API key/token for the selected service. Can also be set via environment variables:
    /// OPENAI_API_KEY, ELEVENLABS_API_KEY, or REPLICATE_API_TOKEN
    #[arg(short, long, env = "API_KEY_PLACEHOLDER", hide_env_values = true)]
    // Placeholder, specific env handled dynamically
    pub api_key_arg: Option<String>,

    /// Speech-to-text service to use
    #[arg(short, long, value_enum, default_value_t = Service::default(), env = "DICTATION_SERVICE")]
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
    #[arg(long, default_value_t = 300, env = "DICTATION_MAX_TIME")]
    pub max_time: u32,

    // --- Resolved values (populated after parsing) ---
    #[clap(skip)]
    pub api_key: String,
}

#[derive(Debug, Clone, Copy, ValueEnum, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum Service {
    #[serde(rename = "openai")]
    OpenAI,
    #[serde(rename = "replicate")]
    Replicate,
    ElevenLabs,
}

impl Service {
    pub fn get_env_var_name(&self) -> &'static str {
        match self {
            Service::Replicate => "REPLICATE_API_TOKEN",
            Service::ElevenLabs => "ELEVENLABS_API_KEY",
            Service::OpenAI => "OPENAI_API_KEY",
        }
    }
}

impl Default for Service {
    fn default() -> Self {
        Service::OpenAI // Default to OpenAI
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
        conf.api_key = conf
            .api_key_arg
            .clone()
            .or_else(|| std::env::var(env_var_name).ok())
            .unwrap_or_default(); // Defaults to empty string if none found
        conf
    }
}
