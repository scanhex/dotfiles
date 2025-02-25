#!/usr/bin/env python3
"""
Whisper Dictation - A lightweight dictation app using OpenAI API with global hotkey support
"""

import os
import sys
import signal
import time
import argparse
import threading
import wave
import json
import tempfile
from pathlib import Path
import pyaudio
import numpy as np
import requests
import pyperclip
from pynput import keyboard

# Output options
OUTPUT_TO_CLIPBOARD = 1
OUTPUT_TO_PASTE = 2
OUTPUT_TO_FILE = 3
OUTPUT_TO_STDOUT = 4

# OpenAI API settings
OPENAI_API_URL = "https://api.openai.com/v1/audio/transcriptions"
OPENAI_API_MODEL = "whisper-1"

# Default recording settings
SAMPLE_RATE = 16000  # 16kHz (appropriate for Whisper API)
CHANNELS = 1  # Mono
CHUNK_SIZE = 1024  # Frames per buffer
FORMAT = pyaudio.paFloat32  # Audio format
MAX_RECORDING_SECONDS = 60  # Maximum recording time

# Global state
g_is_running = True
g_is_recording = False
g_toggle_recording = False
g_api_key = ""
g_output_type = OUTPUT_TO_CLIPBOARD
g_output_file = ""

# Mutex for thread synchronization
g_mutex = threading.Lock()

# Default hotkey settings
DEFAULT_HOTKEY = {"ctrl", "f12"}
g_hotkey = DEFAULT_HOTKEY


class AudioRecorder:
    """Audio recording class using PyAudio"""
    
    def __init__(self, sample_rate=16000, channels=1, chunk_size=1024, format=pyaudio.paFloat32):
        self.sample_rate = sample_rate
        self.channels = channels
        self.chunk_size = chunk_size
        self.format = format
        self.p = pyaudio.PyAudio()
        self.stream = None
        self.frames = []
        self.is_recording = False
        self.thread = None
    
    def start(self):
        """Start recording audio"""
        if self.is_recording:
            return
        
        self.frames = []
        self.is_recording = True
        
        # Open audio stream
        self.stream = self.p.open(
            format=self.format,
            channels=self.channels,
            rate=self.sample_rate,
            input=True,
            frames_per_buffer=self.chunk_size
        )
        
        # Start recording thread
        self.thread = threading.Thread(target=self._record)
        self.thread.daemon = True
        self.thread.start()
        
        print("Recording started...")
    
    def stop(self):
        """Stop recording audio"""
        if not self.is_recording:
            return
        
        self.is_recording = False
        
        # Wait for thread to finish
        if self.thread:
            self.thread.join()
            self.thread = None
        
        # Close stream
        if self.stream:
            self.stream.stop_stream()
            self.stream.close()
            self.stream = None
        
        print("Recording stopped.")
    
    def _record(self):
        """Recording thread function"""
        max_chunks = (self.sample_rate // self.chunk_size) * MAX_RECORDING_SECONDS
        
        while self.is_recording and len(self.frames) < max_chunks:
            try:
                data = self.stream.read(self.chunk_size)
                self.frames.append(np.frombuffer(data, dtype=np.float32))
            except Exception as e:
                print(f"Error recording audio: {e}")
                break
    
    def get_audio_data(self):
        """Get recorded audio data as numpy array"""
        if not self.frames:
            return None
        
        # Concatenate all frames
        audio_data = np.concatenate(self.frames)
        return audio_data
    
    def save_to_wav(self, filename):
        """Save recorded audio to WAV file"""
        audio_data = self.get_audio_data()
        if audio_data is None:
            print("No audio data to save")
            return None
        
        # Convert to int16 for WAV file
        audio_data_int16 = (audio_data * 32767).astype(np.int16)
        
        # Create WAV file
        with wave.open(filename, 'wb') as wf:
            wf.setnchannels(self.channels)
            wf.setsampwidth(2)  # 16-bit
            wf.setframerate(self.sample_rate)
            wf.writeframes(audio_data_int16.tobytes())
        
        return filename
    
    def clear(self):
        """Clear recorded frames"""
        self.frames = []
    
    def close(self):
        """Clean up resources"""
        self.stop()
        self.p.terminate()


def on_hotkey_pressed():
    """Handle hotkey press"""
    global g_toggle_recording, g_mutex
    
    with g_mutex:
        g_toggle_recording = True


def setup_hotkey_listener(hotkey_combo):
    """Set up global hotkey listener"""
    # Create a hotkey combination
    hotkey_mapping = {
        "alt": keyboard.Key.alt,
        "ctrl": keyboard.Key.ctrl,
        "shift": keyboard.Key.shift,
        "cmd": keyboard.Key.cmd,
        "f1": keyboard.Key.f1,
        "f2": keyboard.Key.f2,
        "f3": keyboard.Key.f3,
        "f4": keyboard.Key.f4,
        "f5": keyboard.Key.f5,
        "f6": keyboard.Key.f6,
        "f7": keyboard.Key.f7,
        "f8": keyboard.Key.f8,
        "f9": keyboard.Key.f9,
        "f10": keyboard.Key.f10,
        "f11": keyboard.Key.f11,
        "f12": keyboard.Key.f12,
    }
    
    # Map string keys to actual key objects
    hotkey_set = set()
    for key in hotkey_combo:
        if key in hotkey_mapping:
            hotkey_set.add(hotkey_mapping[key])
        else:
            # For regular keys (letters, numbers, etc.)
            hotkey_set.add(key)
    
    # Create a hotkey listener
    hotkey = keyboard.HotKey(hotkey_set, on_hotkey_pressed)
    
    def for_canonical(f):
        return lambda k: f(listener.canonical(k))
    
    listener = keyboard.Listener(on_press=for_canonical(hotkey.press), on_release=for_canonical(hotkey.release))
    listener.start()
    
    return listener


def keyboard_input_monitor():
    """Monitor keyboard input from stdin as a fallback"""
    global g_is_running, g_toggle_recording, g_mutex
    
    print("Press Enter to toggle recording, or Ctrl+C to quit")
    
    while g_is_running:
        try:
            # Non-blocking input check
            if sys.stdin in select.select([sys.stdin], [], [], 0)[0]:
                line = sys.stdin.readline().strip()
                if line:
                    with g_mutex:
                        g_toggle_recording = True
            
            time.sleep(0.1)  # Sleep to reduce CPU usage
        except (KeyboardInterrupt, EOFError):
            g_is_running = False
            break


def get_xdg_cache_dir():
    """Get XDG cache directory"""
    try:
        from xdg import XDG_CACHE_HOME
        return Path(XDG_CACHE_HOME)
    except ImportError:
        # Fallback if pyxdg is not available
        cache_home = os.environ.get("XDG_CACHE_HOME")
        if cache_home:
            return Path(cache_home)
        return Path(os.path.expanduser("~/.cache"))


def write_to_clipboard(text):
    """Write text to clipboard (cross-platform)"""
    try:
        pyperclip.copy(text)
        print("Text copied to clipboard")
    except Exception as e:
        print(f"Failed to copy to clipboard: {e}")
        # Fallback to platform-specific methods
        if sys.platform == "darwin":  # macOS
            os.system(f'echo "{text}" | pbcopy')
            print("Text copied to clipboard (macOS)")
        elif sys.platform == "win32":  # Windows
            os.system(f'echo {text} | clip')
            print("Text copied to clipboard (Windows)")
        elif sys.platform.startswith("linux"):  # Linux
            # Try different clipboard tools
            if os.system("which xclip > /dev/null 2>&1") == 0:
                os.system(f'echo "{text}" | xclip -selection clipboard')
                print("Text copied to clipboard (Linux/X11 - xclip)")
            elif os.system("which xsel > /dev/null 2>&1") == 0:
                os.system(f'echo "{text}" | xsel -ib')
                print("Text copied to clipboard (Linux/X11 - xsel)")
            elif os.system("which wl-copy > /dev/null 2>&1") == 0:
                os.system(f'echo "{text}" | wl-copy')
                print("Text copied to clipboard (Linux/Wayland)")
            else:
                print("No clipboard tool found. Text saved to /tmp/whisper_clipboard.txt")
                with open("/tmp/whisper_clipboard.txt", "w") as f:
                    f.write(text)


def direct_type_text(text):
    """Type text directly to the active application"""
    if not text:
        return
    
    print(f"Typing text: {text}")
    
    # First copy to clipboard
    write_to_clipboard(text)
    
    # Then paste using platform-specific methods
    if sys.platform == "darwin":  # macOS
        cmd = """
        osascript -e 'tell application "System Events" to keystroke "v" using command down'
        """
        os.system(cmd)
        print("Text pasted (macOS)")
    
    elif sys.platform == "win32":  # Windows
        import ctypes
        from ctypes import wintypes
        user32 = ctypes.WinDLL('user32', use_last_error=True)
        
        # Input type constants
        INPUT_KEYBOARD = 1
        KEYEVENTF_KEYUP = 0x0002
        
        # Virtual key codes
        VK_CONTROL = 0x11
        VK_V = 0x56
        
        # Input structure
        class INPUT(ctypes.Structure):
            _fields_ = (("type", wintypes.DWORD),
                       ("ki", ctypes.c_byte * 28))
        
        # Create input array
        inputs = (INPUT * 4)()
        
        inputs[0].type = INPUT_KEYBOARD
        inputs[0].ki[0] = VK_CONTROL
        
        inputs[1].type = INPUT_KEYBOARD
        inputs[1].ki[0] = VK_V
        
        inputs[2].type = INPUT_KEYBOARD
        inputs[2].ki[0] = VK_V
        inputs[2].ki[1] = KEYEVENTF_KEYUP
        
        inputs[3].type = INPUT_KEYBOARD
        inputs[3].ki[0] = VK_CONTROL
        inputs[3].ki[1] = KEYEVENTF_KEYUP
        
        user32.SendInput(4, ctypes.byref(inputs), ctypes.sizeof(INPUT))
        print("Text pasted (Windows)")
    
    elif sys.platform.startswith("linux"):  # Linux
        # Use xdotool if available
        if os.system("which xdotool > /dev/null 2>&1") == 0:
            os.system('xdotool key ctrl+v')
            print("Text pasted (Linux)")
        else:
            print("Could not paste text directly. xdotool is not available.")


def process_output(text):
    """Process the transcribed text based on output settings"""
    if not text:
        return
    
    global g_output_type, g_output_file
    
    if g_output_type == OUTPUT_TO_CLIPBOARD:
        print(f"Copying to clipboard: {text}")
        write_to_clipboard(text)
    
    elif g_output_type == OUTPUT_TO_PASTE:
        print(f"Pasting to active window: {text}")
        direct_type_text(text)
    
    elif g_output_type == OUTPUT_TO_FILE:
        if g_output_file:
            print(f"Writing to file: {g_output_file}")
            with open(g_output_file, "a") as f:
                f.write(text + "\n")
        else:
            print("No output file specified.")
    
    elif g_output_type == OUTPUT_TO_STDOUT:
        print(f"Transcript: {text}")


def transcribe_with_openai(audio_file_path):
    """Transcribe audio using OpenAI Whisper API"""
    global g_api_key
    
    if not g_api_key:
        print("Error: OpenAI API key not set. Use --api-key option.")
        return None
    
    headers = {
        "Authorization": f"Bearer {g_api_key}"
    }
    
    with open(audio_file_path, "rb") as f:
        files = {
            "file": (os.path.basename(audio_file_path), f, "audio/wav"),
            "model": (None, OPENAI_API_MODEL)
        }
        
        print("Sending audio to OpenAI API for transcription...")
        
        try:
            response = requests.post(
                OPENAI_API_URL,
                headers=headers,
                files=files
            )
            
            response.raise_for_status()
            result = response.json()
            
            if "text" in result:
                return result["text"]
            else:
                print(f"Error: API response missing 'text' field: {result}")
                return None
        
        except requests.exceptions.RequestException as e:
            print(f"Error: Failed to transcribe audio: {e}")
            if hasattr(e, "response") and e.response:
                print(f"Response: {e.response.text}")
            return None


def signal_handler(signum, frame):
    """Handle interrupt signals"""
    global g_is_running
    
    if signum == signal.SIGINT:
        print("\nCaught SIGINT, stopping application...")
        g_is_running = False


def main():
    """Main application function"""
    global g_api_key, g_output_type, g_output_file, g_hotkey, g_is_running, g_is_recording, g_toggle_recording, g_mutex
    
    # Set up argument parser
    parser = argparse.ArgumentParser(description="Whisper Dictation - A lightweight dictation app using OpenAI API")
    parser.add_argument("-k", "--api-key", help="OpenAI API key")
    parser.add_argument("-o", "--output", choices=["clipboard", "paste", "file", "stdout"], default="clipboard", help="Output type")
    parser.add_argument("-f", "--file", help="Output file path (for file output type)")
    parser.add_argument("-m", "--mod", help="Modifier key for hotkey (ctrl, alt, shift, cmd)")
    parser.add_argument("-g", "--key", help="Key for hotkey (f1-f12, etc.)")
    args = parser.parse_args()
    
    # Set API key from arguments or environment variable
    api_key = args.api_key or os.environ.get("OPENAI_API_KEY")
    if api_key:
        g_api_key = api_key
    else:
        print("Error: No OpenAI API key provided. Set with --api-key or OPENAI_API_KEY environment variable.")
        return 1
    
    # Set output type
    if args.output == "clipboard":
        g_output_type = OUTPUT_TO_CLIPBOARD
    elif args.output == "paste":
        g_output_type = OUTPUT_TO_PASTE
    elif args.output == "file":
        g_output_type = OUTPUT_TO_FILE
        if args.file:
            g_output_file = args.file
        else:
            g_output_file = "whisper_output.txt"
            print(f"Warning: No output file specified, defaulting to {g_output_file}")
    elif args.output == "stdout":
        g_output_type = OUTPUT_TO_STDOUT
    
    # Set hotkey
    hotkey = DEFAULT_HOTKEY
    if args.mod and args.key:
        hotkey = {args.mod, args.key}
    
    # Set up signal handler
    signal.signal(signal.SIGINT, signal_handler)
    
    # Start hotkey listener
    hotkey_listener = setup_hotkey_listener(hotkey)
    
    # Create temporary directory for audio files
    temp_dir = Path(tempfile.gettempdir()) / "whisper_dictation"
    temp_dir.mkdir(exist_ok=True)
    
    # Set up audio recorder
    recorder = AudioRecorder(
        sample_rate=SAMPLE_RATE,
        channels=CHANNELS,
        chunk_size=CHUNK_SIZE,
        format=FORMAT
    )
    
    # Start input monitoring thread
    input_thread = threading.Thread(target=keyboard_input_monitor)
    input_thread.daemon = True
    input_thread.start()
    
    print(f"Whisper Dictation - Press the hotkey or Enter to start/stop recording")
    print(f"Using OpenAI API for transcription (Whisper API)")
    print(f"Temporary audio files will be stored in {temp_dir}")
    
    # Main loop
    active_recording = False
    
    try:
        while g_is_running:
            # Check if recording toggle requested
            with g_mutex:
                toggle_requested = g_toggle_recording
                if toggle_requested:
                    g_is_recording = not g_is_recording
                    g_toggle_recording = False
                should_record = g_is_recording
            
            # Start/stop recording based on toggle state
            if should_record and not active_recording:
                print("Starting recording session...")
                recorder.start()
                active_recording = True
            elif not should_record and active_recording:
                print("Stopping recording session...")
                recorder.stop()
                active_recording = False
                
                # Process the recorded audio
                wav_path = temp_dir / f"recording_{int(time.time())}.wav"
                recorder.save_to_wav(str(wav_path))
                
                # Transcribe audio
                transcription = transcribe_with_openai(str(wav_path))
                
                if transcription:
                    # Process output
                    process_output(transcription)
                else:
                    print("Failed to get transcription from OpenAI API.")
                
                # Remove temporary WAV file
                try:
                    os.remove(wav_path)
                except Exception as e:
                    print(f"Warning: Failed to remove temporary file: {e}")
                
                # Clear recorder for next session
                recorder.clear()
            
            # Sleep to reduce CPU usage
            time.sleep(0.05)
    
    except KeyboardInterrupt:
        print("\nExiting...")
    
    finally:
        # Clean up
        if active_recording:
            recorder.stop()
        
        recorder.close()
        
        # Stop hotkey listener
        hotkey_listener.stop()
        
        # Clean up temporary directory if empty
        try:
            temp_dir.rmdir()
        except:
            pass
    
    return 0


if __name__ == "__main__":
    # Import select only when needed (on keyboard_input_monitor)
    import select
    sys.exit(main())