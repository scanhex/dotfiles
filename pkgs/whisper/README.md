# Whisper Dictation

A lightweight dictation application using OpenAI's Whisper API for speech-to-text conversion with global hotkey support.

## Features

- Real-time dictation using OpenAI's Whisper API
- Global hotkey support (toggle recording with a keyboard shortcut)
  - Cross-compositor support (X11 and Wayland)
- Multiple output options:
  - Copy to clipboard
  - Direct paste to current application (with smart character-by-character typing)
  - Write to file
  - Output to stdout
- Cross-platform support (Linux, macOS, Windows)
- Intelligent text input detection (types text character-by-character in text applications)

## Prerequisites

- Python 3.7+
- OpenAI API key
- Required Python packages (installed automatically with Nix)
- Python dependencies (installed automatically with Nix):
  - PyAudio (for audio recording)
  - Pynput (for hotkey detection and keyboard simulation)
  - Python-xlib (for X11 window detection)
  - Evdev (for Wayland keyboard support)
  - Numpy, requests, pyperclip (for auxiliary functionality)

## Installation

Using Nix:

```bash
nix build
```

## Usage

Run the application:

```bash
./result/bin/whisper-dictation -k YOUR_OPENAI_API_KEY
```

Or set the API key as an environment variable:

```bash
export OPENAI_API_KEY=your_api_key
./result/bin/whisper-dictation
```

### Command-line Options

- `-k, --api-key`: OpenAI API key (can also use OPENAI_API_KEY environment variable)
- `-o, --output`: Output type (choices: clipboard, paste, file, stdout)
- `-f, --file`: Output file path (for file output type)
- `-m, --mod`: Modifier key for hotkey (ctrl, alt, shift, cmd)
- `-g, --key`: Key for hotkey (f1-f12, etc.)

### Default Hotkey

The default hotkey combination is `Ctrl+F11`. Press it once to start recording, and again to stop recording and process the audio.

### Smart Text Input

When using the "paste" output mode, the application will:
1. Detect if the current application is a text input program
2. If it is, type each character individually (better for applications like terminal emulators)
3. Otherwise, fall back to using clipboard paste (Ctrl+V or Command+V)

## License

MIT

## Notes

This application requires an internet connection as it uses the OpenAI API for speech recognition.