# Whisper Dictation

A lightweight dictation application using [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for speech recognition and PortAudio for cross-platform audio capture.

## Features

- Real-time dictation using OpenAI's Whisper speech recognition model
- Lightweight C implementation
- Cross-platform support via PortAudio
- Local processing (no internet required)

## Prerequisites

- Whisper.cpp model file (see Installation)
- A C compiler
- PortAudio library

## Installation

1. Download a Whisper model:

```bash
mkdir -p models
wget -P models https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin
```

2. Build the application:

```bash
nix build
```

Or build manually:

```bash
cc -o whisper-dictation main.c whisper.c recording.c -lportaudio -lm -pthread -O3
```

## Usage

Run the application:

```bash
./result/bin/whisper-dictation
```

Press Ctrl+C to stop recording.

## Integration with whisper.cpp

The current implementation includes a mock whisper interface. To integrate with the actual whisper.cpp library:

1. Clone the whisper.cpp repository:
```bash
git clone https://github.com/ggerganov/whisper.cpp.git
```

2. Modify the build command to link against the whisper.cpp implementation:
```bash
cc -o whisper-dictation main.c recording.c -Iwhisper.cpp whisper.cpp/whisper.cpp -lportaudio -lm -pthread -O3
```

## License

MIT

## Notes

This is a simple dictation application built for easy isolation or migration to a separate repository in the future.