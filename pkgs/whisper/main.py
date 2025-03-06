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

# API service options
SERVICE_REPLICATE = 1
SERVICE_ELEVENLABS = 2

# Replicate API settings
REPLICATE_API_URL = "https://api.replicate.com/v1/predictions"
REPLICATE_MODEL_VERSION = "3ab86df6c8f54c11309d4d1f930ac292bad43ace52d10c80d87eb258b3c9f79c"

# ElevenLabs API settings
ELEVENLABS_API_URL = "https://api.elevenlabs.io/v1/speech-to-text"
ELEVENLABS_MODEL = "scribe_v1"  # Currently only scribe_v1 is supported

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
g_service = SERVICE_ELEVENLABS  # Default to ElevenLabs
g_output_type = OUTPUT_TO_CLIPBOARD
g_output_file = ""

# Mutex for thread synchronization
g_mutex = threading.Lock()

# Default hotkey settings
DEFAULT_MODIFIER = keyboard.Key.ctrl
DEFAULT_KEY = keyboard.Key.f11


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


class GlobalHotkeyListener:
    """Global hotkey listener implementation with Wayland support"""
    
    def __init__(self, modifier_key, main_key):
        self.modifier_pressed = False
        self.modifier_key = modifier_key
        self.main_key = main_key
        self.listener = None
        self.is_evdev_available = False
        self.evdev_thread = None
        self.is_running = True
        
        # Try to determine if we're running under Wayland
        self.is_wayland = 'WAYLAND_DISPLAY' in os.environ
        
        # Keep track of evdev devices if using evdev
        self.evdev_devices = []
    
    def on_press(self, key):
        """Handle key press events for X11/non-Wayland"""
        try:
            # Debug output for key presses
            # print(f"Key pressed: {key}")
            
            # Check if this is our modifier key
            if key == self.modifier_key:
                self.modifier_pressed = True
            
            # If modifier is pressed and this is our main key, trigger the action
            elif self.modifier_pressed and key == self.main_key:
                with g_mutex:
                    global g_toggle_recording
                    g_toggle_recording = True
                    print("Hotkey combination detected! Toggling recording...")
        except Exception as e:
            print(f"Error in hotkey listener: {e}")
        
        return True  # Continue listening
    
    def on_release(self, key):
        """Handle key release events for X11/non-Wayland"""
        try:
            if key == self.modifier_key:
                self.modifier_pressed = False
        except Exception as e:
            print(f"Error in hotkey listener: {e}")
        
        return True  # Continue listening
    
    def _run_evdev_listener(self):
        """Run evdev-based keyboard listener for Wayland"""
        try:
            from evdev import InputDevice, categorize, ecodes, list_devices, KeyEvent
            import select
            
            # Map pynput Key objects to evdev key codes
            ctrl_keys = [ecodes.KEY_LEFTCTRL, ecodes.KEY_RIGHTCTRL]
            alt_keys = [ecodes.KEY_LEFTALT, ecodes.KEY_RIGHTALT]
            shift_keys = [ecodes.KEY_LEFTSHIFT, ecodes.KEY_RIGHTSHIFT]
            meta_keys = [ecodes.KEY_LEFTMETA, ecodes.KEY_RIGHTMETA]
            
            # Determine which modifier keys to listen for
            modifier_keys = []
            if self.modifier_key == keyboard.Key.ctrl:
                modifier_keys = ctrl_keys
            elif self.modifier_key == keyboard.Key.alt:
                modifier_keys = alt_keys
            elif self.modifier_key == keyboard.Key.shift:
                modifier_keys = shift_keys
            elif self.modifier_key == keyboard.Key.cmd:
                modifier_keys = meta_keys
            
            # Determine main key to listen for
            main_key = None
            if self.main_key == keyboard.Key.f1:
                main_key = ecodes.KEY_F1
            elif self.main_key == keyboard.Key.f2:
                main_key = ecodes.KEY_F2
            elif self.main_key == keyboard.Key.f3:
                main_key = ecodes.KEY_F3
            elif self.main_key == keyboard.Key.f4:
                main_key = ecodes.KEY_F4
            elif self.main_key == keyboard.Key.f5:
                main_key = ecodes.KEY_F5
            elif self.main_key == keyboard.Key.f6:
                main_key = ecodes.KEY_F6
            elif self.main_key == keyboard.Key.f7:
                main_key = ecodes.KEY_F7
            elif self.main_key == keyboard.Key.f8:
                main_key = ecodes.KEY_F8
            elif self.main_key == keyboard.Key.f9:
                main_key = ecodes.KEY_F9
            elif self.main_key == keyboard.Key.f10:
                main_key = ecodes.KEY_F10
            elif self.main_key == keyboard.Key.f11:
                main_key = ecodes.KEY_F11
            elif self.main_key == keyboard.Key.f12:
                main_key = ecodes.KEY_F12
            
            # Check if we found a valid mapping
            if not modifier_keys or main_key is None:
                print("Warning: Could not map hotkey to evdev keys. Falling back to standard listener.")
                return
            
            # Find keyboard devices
            devices = []
            try:
                device_paths = list_devices()
                for path in device_paths:
                    try:
                        device = InputDevice(path)
                        if ecodes.EV_KEY in device.capabilities():
                            # This is likely a keyboard or has keyboard-like input
                            devices.append(device)
                            print(f"Found input device: {device.path} ({device.name})")
                    except Exception as e:
                        print(f"Error opening device {path}: {e}")
            except Exception as e:
                print(f"Error listing input devices: {e}")
            
            if not devices:
                print("Warning: No input devices found. Evdev listener will not work.")
                return
            
            # Store devices for cleanup
            self.evdev_devices = devices
            
            print(f"Evdev listener started with {len(devices)} devices")
            print(f"Listening for modifier keys {modifier_keys} and main key {main_key}")
            
            # Track modifier state
            modifier_state = False
            
            # Main evdev listening loop
            while self.is_running:
                # Wait for events on any device with a 0.1 second timeout
                r, w, x = select.select(devices, [], [], 0.1)
                
                for device in r:
                    try:
                        for event in device.read():
                            if event.type == ecodes.EV_KEY:
                                key_event = categorize(event)
                                
                                # Check for modifier keys
                                if key_event.scancode in modifier_keys:
                                    modifier_state = key_event.keystate == KeyEvent.key_down
                                
                                # Check for main key when modifier is pressed
                                elif key_event.scancode == main_key and key_event.keystate == KeyEvent.key_down:
                                    if modifier_state:
                                        with g_mutex:
                                            global g_toggle_recording
                                            g_toggle_recording = True
                                            print("Hotkey combination detected (evdev)! Toggling recording...")
                    except Exception as e:
                        print(f"Error reading from device {device.path}: {e}")
        
        except ImportError:
            print("Warning: evdev package not available. Wayland hotkeys will not work.")
            print("Install evdev package to enable Wayland support.")
        except Exception as e:
            print(f"Error in evdev listener: {e}")
    
    def start(self):
        """Start the keyboard listener with appropriate backend"""
        if self.is_wayland:
            try:
                # Try to import evdev
                import evdev
                import select
                self.is_evdev_available = True
            except ImportError:
                self.is_evdev_available = False
                print("Warning: evdev package not installed. Hotkeys may not work under Wayland.")
                print("Install evdev package for Wayland support.")
        
        if self.is_wayland and self.is_evdev_available:
            # Use evdev for Wayland
            print("Starting evdev-based hotkey listener for Wayland")
            self.evdev_thread = threading.Thread(target=self._run_evdev_listener)
            self.evdev_thread.daemon = True
            self.evdev_thread.start()
        else:
            # Use pynput for X11 and other platforms
            print("Starting pynput-based hotkey listener")
            self.listener = keyboard.Listener(on_press=self.on_press, on_release=self.on_release)
            self.listener.daemon = True
            self.listener.start()
    
    def stop(self):
        """Stop the keyboard listener"""
        self.is_running = False
        
        if self.listener:
            self.listener.stop()
        
        if self.evdev_thread:
            self.evdev_thread.join(timeout=1.0)
            
        # Close any open evdev devices
        for device in self.evdev_devices:
            try:
                device.close()
            except:
                pass


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
                        print("Toggle recording requested from keyboard")
            
            time.sleep(0.1)  # Sleep to reduce CPU usage
        except (KeyboardInterrupt, EOFError):
            g_is_running = False
            break


def get_cache_dir():
    """Get cross-platform cache directory"""
    if sys.platform == "darwin":  # macOS
        return Path(os.path.expanduser("~/Library/Caches/whisper_dictation"))
    elif sys.platform == "win32":  # Windows
        return Path(os.path.expanduser("~/AppData/Local/whisper_dictation/Cache"))
    else:  # Linux and others (XDG)
        cache_home = os.environ.get("XDG_CACHE_HOME")
        if cache_home:
            return Path(cache_home) / "whisper_dictation"
        return Path(os.path.expanduser("~/.cache/whisper_dictation"))


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


def is_text_application():
    """Detect if the current application is a text editor or text input program"""
    try:
        if sys.platform == "darwin":  # macOS
            # Get the front app name using AppleScript
            cmd = """
            osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true'
            """
            app_name = os.popen(cmd).read().strip().lower()
            
            # List of known text applications
            text_apps = [
                "textedit", "pages", "notes", "word", "vscode", "sublime text", 
                "atom", "visual studio code", "terminal", "iterm", "terminal",
                "vim", "emacs", "neovim", "textmate", "typora", "slack", "discord",
                "chrome", "firefox", "safari", "edge", "brave", "zed"
            ]
            
            return any(app in app_name for app in text_apps)
            
        elif sys.platform == "win32":  # Windows
            import ctypes
            import ctypes.wintypes
            
            # Get foreground window handle
            hwnd = ctypes.windll.user32.GetForegroundWindow()
            
            # Get window class name
            class_name = ctypes.create_unicode_buffer(256)
            ctypes.windll.user32.GetClassNameW(hwnd, class_name, 256)
            
            # Get window title
            title_length = ctypes.windll.user32.GetWindowTextLengthW(hwnd)
            title = ctypes.create_unicode_buffer(title_length + 1)
            ctypes.windll.user32.GetWindowTextW(hwnd, title, title_length + 1)
            
            # List of known text application class names and title patterns
            text_classes = [
                "Notepad", "WordPadClass", "XLMAIN", "OpusApp", "Chrome_WidgetWin",
                "MozillaWindowClass", "Vim", "Emacs", "Sublime_Text", "VSCodeFrameClass",
                "ConsoleWindowClass", "Xshell", "PuTTY", "mintty", "VanDyke Software.SecureCRT"
            ]
            
            text_title_patterns = [
                "editor", "notepad", "word", "text", "document", "code", "terminal",
                "cmd", "powershell", "putty", "shell", "bash", "vim", "emacs", "vscode",
                "sublime", "atom", "zed"
            ]
            
            return (any(cls.lower() in class_name.value.lower() for cls in text_classes) or
                    any(pattern in title.value.lower() for pattern in text_title_patterns))
            
        elif sys.platform.startswith("linux"):  # Linux
            try:
                # Use python-xlib to get active window info
                from Xlib import display, X
                from Xlib.error import DisplayError, BadWindow
                
                d = display.Display()
                root = d.screen().root
                
                # Get active window ID
                active_window_id = root.get_full_property(
                    d.intern_atom('_NET_ACTIVE_WINDOW'), X.AnyPropertyType
                ).value[0]
                
                # Get window properties
                window_obj = d.create_resource_object('window', active_window_id)
                
                # Get window class
                window_class = window_obj.get_wm_class()
                window_class_str = ' '.join(window_class).lower() if window_class else ''
                
                # Get window name
                window_name = window_obj.get_wm_name()
                window_name_str = window_name.lower() if window_name else ''
                
                print(f"Window class: {window_class_str}, name: {window_name_str}")
                
                # List of known text application class and title patterns
                text_classes = [
                    "gedit", "kwrite", "kate", "leafpad", "mousepad", "pluma", "vim",
                    "emacs", "sublime", "atom", "code", "terminal", "gnome-terminal",
                    "konsole", "xterm", "rxvt", "firefox", "chrome", "chromium", "brave",
                    "discord", "slack", "libreoffice", "org.wezfurlong.wezterm"
                ]
                
                text_title_patterns = [
                    "editor", "text", "document", "terminal", "console", "shell", "bash",
                    "zsh", "vim", "emacs", "vscode", "sublime", "atom", "zed"
                ]
                
                return (any(cls in window_class_str for cls in text_classes) or
                        any(pattern in window_name_str for pattern in text_title_patterns))
                        
            except (ImportError, DisplayError, BadWindow) as e:
                print(f"Error with X11 window detection: {e}")
                # Fallback: assume it's a text app
                return True
    
    except Exception as e:
        print(f"Error detecting application type: {e}")
        # Default to safe option - assume it's a text app
        return True


def type_text_char_by_char(text):
    """Type text character by character using keyboard emulation"""
    if not text:
        return False
    
    try:
        # Use pynput as the primary method
        try:
            from pynput.keyboard import Controller, Key
            
            keyboard = Controller()
            
            # Brief delay before typing
            time.sleep(0.2)
            
            for char in text:
                if char == '\n':
                    keyboard.press(Key.enter)
                    keyboard.release(Key.enter)
                elif char == '\t':
                    keyboard.press(Key.tab)
                    keyboard.release(Key.tab)
                else:
                    keyboard.press(char)
                    keyboard.release(char)
                
                time.sleep(0.001)
            
            return True
                
        except Exception as e:
            print(f"Cannot type character by character using pynput: {e}")
            return False
    
    except Exception as e:
        print(f"Error typing text character by character: {e}")
        return False


def is_wayland():
    return 'WAYLAND_DISPLAY' in os.environ

def direct_type_text(text):
    """Type text directly to the active application"""
    if not text:
        return
    
    print(f"Typing text: {text}")
    
    # Check if current application is a text app
    is_text_app = is_text_application()
    print(f"Current application appears to be a text application: {is_text_app}")
    
    # Try to type character by character if it's a text app
    if is_text_app:
        if is_wayland():
            os.system(f'wtype "{text}"')
            print('Text typed using wtype')
            return
        elif type_text_char_by_char(text):
            print("Text typed character by character")
            return
    
    # Fall back to clipboard paste method
    print("Falling back to clipboard paste method")
    
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
        try:
            # Try using pynput to simulate Ctrl+V
            from pynput.keyboard import Controller, Key
            
            keyboard = Controller()
            
            # Press Ctrl+V
            keyboard.press(Key.ctrl)
            keyboard.press('v')
            keyboard.release('v')
            keyboard.release(Key.ctrl)
            
            print("Text pasted using pynput (Linux)")
        except Exception as e:
            print(f"Could not paste text directly: {e}")


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


def transcribe_with_elevenlabs(audio_file_path, max_retries=3, retry_delay=2):
    """Transcribe audio using ElevenLabs API with retry logic"""
    global g_api_key
    
    if not g_api_key:
        print("Error: ElevenLabs API key not set. Use --api-key option.")
        return None
    
    headers = {
        "xi-api-key": g_api_key,
        "Accept": "application/json"
    }
    
    print(f"Sending audio to ElevenLabs API for transcription (with {max_retries} retries)...")
    
    # Check if the audio file is valid
    try:
        with wave.open(audio_file_path, 'rb') as wf:
            # Get basic info about the WAV file
            channels = wf.getnchannels()
            sampwidth = wf.getsampwidth()
            framerate = wf.getframerate()
            frames = wf.getnframes()
            
            # Print audio file info
            print(f"Audio file info: {frames} frames, {framerate} Hz, {channels} channels, {sampwidth} bytes/sample")
            
            # Check if the audio file has content
            if frames == 0:
                print("Error: Audio file contains no frames")
                return None
                
            # Check duration in seconds
            duration = frames / float(framerate)
            print(f"Audio duration: {duration:.2f} seconds")
            
            if duration < 0.5:
                print("Error: Audio file is too short (less than 0.5 seconds)")
                return None
    except Exception as e:
        print(f"Error checking audio file: {e}")
        return None
        
    # Create multipart form data
    with open(audio_file_path, "rb") as f:
        audio_content = f.read()
    
    # Print audio file size
    print(f"Audio file size: {len(audio_content)} bytes")
    
    files = {
        'file': ('audio.wav', audio_content, 'audio/wav'),
    }
    
    data = {
        'model_id': ELEVENLABS_MODEL,
        'language_code': 'en',  # Default to English
        'tag_audio_events': 'false',  # Don't tag audio events like laughter
        'diarize': 'false'  # Don't annotate who is speaking
    }
    
    result = None
    
    # Implement retry logic
    for attempt in range(max_retries):
        try:
            if attempt > 0:
                print(f"Retry attempt {attempt+1}/{max_retries} for ElevenLabs API...")
                time.sleep(retry_delay * attempt)  # Exponential backoff
            
            # Send request to ElevenLabs API
            response = requests.post(
                ELEVENLABS_API_URL,
                headers=headers,
                files=files,
                data=data,
                timeout=30  # Add timeout to prevent hanging
            )
            
            # Print detailed response info for debugging
            print(f"ElevenLabs API Status Code: {response.status_code}")
            
            # For rate limiting (429) or server errors (5xx), retry
            if response.status_code == 429 or (response.status_code >= 500 and response.status_code < 600):
                print(f"Received status code {response.status_code}, will retry...")
                continue
                
            response.raise_for_status()
            result = response.json()
            
            # Print the full response for debugging
            print(f"ElevenLabs Response Content: {json.dumps(result, indent=2)}")
            
            # Success, exit retry loop
            break
            
        except requests.exceptions.RequestException as e:
            print(f"Error on attempt {attempt+1}: {e}")
            if hasattr(e, "response") and e.response:
                try:
                    error_json = e.response.json()
                    print(f"Response status: {e.response.status_code}")
                    print(f"Error details: {json.dumps(error_json, indent=2)}")
                except:
                    print(f"Response text: {e.response.text}")
            
            # Only retry on connection errors, timeouts, or 5xx server errors
            if isinstance(e, (requests.exceptions.ConnectionError, 
                             requests.exceptions.Timeout)) or \
               (hasattr(e, "response") and e.response and 500 <= e.response.status_code < 600):
                if attempt < max_retries - 1:  # Not the last attempt
                    continue
            
            # For other exceptions, give up
            return None
    
    # Extract transcription text from results
    if result and "text" in result:
        if result["text"].strip():  # Check if text is not empty
            return result["text"]
        else:
            print("Error: ElevenLabs returned empty transcription text")
            return None
    else:
        if result:
            print(f"Error: Unexpected response format from ElevenLabs: {json.dumps(result, indent=2)}")
            # Check for common error fields
            if "error" in result:
                print(f"ElevenLabs Error: {result['error']}")
            elif "detail" in result:
                print(f"ElevenLabs Error Detail: {result['detail']}")
        else:
            print(f"Error: Failed to get a valid response from ElevenLabs after {max_retries} attempts")
        return None


def transcribe_with_replicate(audio_file_path, max_retries=3, retry_delay=2):
    """Transcribe audio using Replicate Whisper API with retry logic"""
    global g_api_key
    
    if not g_api_key:
        print("Error: Replicate API token not set. Use --api-key option.")
        return None
    
    headers = {
        "Authorization": f"Bearer {g_api_key}",
        "Content-Type": "application/json"
    }
    
    # Check if the audio file is valid
    try:
        with wave.open(audio_file_path, 'rb') as wf:
            # Get basic info about the WAV file
            channels = wf.getnchannels()
            sampwidth = wf.getsampwidth()
            framerate = wf.getframerate()
            frames = wf.getnframes()
            
            # Print audio file info
            print(f"Audio file info: {frames} frames, {framerate} Hz, {channels} channels, {sampwidth} bytes/sample")
            
            # Check if the audio file has content
            if frames == 0:
                print("Error: Audio file contains no frames")
                return None
                
            # Check duration in seconds
            duration = frames / float(framerate)
            print(f"Audio duration: {duration:.2f} seconds")
            
            if duration < 0.5:
                print("Error: Audio file is too short (less than 0.5 seconds)")
                return None
    except Exception as e:
        print(f"Error checking audio file: {e}")
        return None
        
    # First upload the file to Replicate
    with open(audio_file_path, "rb") as f:
        # Convert audio to base64 (suitable for small files)
        import base64
        audio_content = f.read()
        
        # Print audio file size
        print(f"Audio file size: {len(audio_content)} bytes")
        
        audio_base64 = base64.b64encode(audio_content).decode('utf-8')
        audio_data_uri = f"data:audio/wav;base64,{audio_base64}"
    
    # Create the prediction request JSON
    data = {
        "version": REPLICATE_MODEL_VERSION,
        "input": {
            "audio": audio_data_uri,
            "batch_size": 64
        }
    }
    
    print(f"Sending audio to Replicate API for transcription (with {max_retries} retries)...")
    
    prediction_id = None
    
    # Try to create prediction with retries
    for attempt in range(max_retries):
        try:
            if attempt > 0:
                print(f"Retry attempt {attempt+1}/{max_retries} for creating prediction...")
                time.sleep(retry_delay * attempt)  # Exponential backoff
                
            # Create the prediction
            response = requests.post(
                REPLICATE_API_URL,
                headers=headers,
                json=data,
                timeout=30  # Add timeout to prevent hanging
            )
            
            # Print detailed response info for debugging
            print(f"Replicate API Status Code: {response.status_code}")
            
            # For rate limiting (429) or server errors (5xx), retry
            if response.status_code == 429 or (response.status_code >= 500 and response.status_code < 600):
                print(f"Received status code {response.status_code}, will retry...")
                continue
                
            response.raise_for_status()
            result = response.json()
            prediction_id = result.get("id")
            
            if not prediction_id:
                print(f"Error: Failed to create prediction: {result}")
                if attempt < max_retries - 1:
                    continue
                return None
                
            # Successfully created prediction
            break
                
        except requests.exceptions.RequestException as e:
            print(f"Error creating prediction on attempt {attempt+1}: {e}")
            if hasattr(e, "response") and e.response:
                try:
                    error_json = e.response.json()
                    print(f"Response status: {e.response.status_code}")
                    print(f"Error details: {json.dumps(error_json, indent=2)}")
                except:
                    print(f"Response text: {e.response.text}")
            
            # Only retry on connection errors, timeouts, or 5xx server errors
            if isinstance(e, (requests.exceptions.ConnectionError, 
                             requests.exceptions.Timeout)) or \
               (hasattr(e, "response") and e.response and 500 <= e.response.status_code < 600):
                if attempt < max_retries - 1:  # Not the last attempt
                    continue
            
            # For other exceptions, give up
            return None
    
    if not prediction_id:
        print("Failed to create prediction after all retries")
        return None
            
    # Poll for the prediction result
    get_url = f"{REPLICATE_API_URL}/{prediction_id}"
    max_poll_attempts = 60
    poll_attempt = 0
    
    while poll_attempt < max_poll_attempts:
        poll_attempt += 1
        
        try:
            # Wait before polling - shorter interval for faster response
            time.sleep(0.3)
            
            # Get prediction status
            get_response = requests.get(
                get_url,
                headers=headers,
                timeout=10  # Add timeout to prevent hanging
            )
            
            if get_response.status_code != 200:
                print(f"Error polling prediction: Status code {get_response.status_code}")
                try:
                    error_json = get_response.json()
                    print(f"Error details: {json.dumps(error_json, indent=2)}")
                except:
                    print(f"Response text: {get_response.text}")
                # For server errors, wait a bit longer before retrying
                if 500 <= get_response.status_code < 600:
                    time.sleep(1)
                continue
                
            prediction = get_response.json()
            status = prediction.get("status")
            
            # Check status
            if status == "succeeded":
                # Extract text from output
                output = prediction.get("output", {})
                if isinstance(output, dict) and "text" in output:
                    # The model returns both chunks and a combined text field
                    # Just use the text field directly to avoid duplication
                    return output["text"]
                elif isinstance(output, dict) and "chunks" in output:
                    # Only use chunks if there's no full text field
                    chunks = output.get("chunks", [])
                    if chunks:
                        return " ".join(chunk.get("text", "") for chunk in chunks).strip()
                    return ""
                else:
                    # Handle direct text output
                    return output
            elif status == "failed":
                print(f"Prediction failed: {prediction.get('error')}")
                return None
            elif status == "canceled":
                print("Prediction was canceled")
                return None
                
        except requests.exceptions.RequestException as e:
            print(f"Error polling prediction: {e}")
            if hasattr(e, "response") and e.response:
                try:
                    error_json = e.response.json()
                    print(f"Response status: {e.response.status_code}")
                    print(f"Error details: {json.dumps(error_json, indent=2)}")
                except:
                    print(f"Response text: {e.response.text}")
            # Brief pause before retrying poll
            time.sleep(1)
                
    print(f"Prediction timed out after {max_poll_attempts} polling attempts")
    return None


def signal_handler(signum, frame):
    """Handle interrupt signals"""
    global g_is_running
    
    if signum == signal.SIGINT:
        print("\nCaught SIGINT, stopping application...")
        g_is_running = False


def main():
    """Main application function"""
    global g_api_key, g_output_type, g_output_file, g_is_running, g_is_recording, g_toggle_recording, g_mutex
    
    # Set up argument parser
    parser = argparse.ArgumentParser(description="Whisper Dictation - A lightweight dictation app using speech-to-text APIs")
    parser.add_argument("-k", "--api-key", help="API token for selected service")
    parser.add_argument("-s", "--service", choices=["replicate", "elevenlabs"], default="elevenlabs", 
                      help="Speech-to-text service to use (default: elevenlabs)")
    parser.add_argument("-o", "--output", choices=["clipboard", "paste", "file", "stdout"], default="clipboard", 
                      help="Output type (paste will use character-by-character input for text applications)")
    parser.add_argument("-f", "--file", help="Output file path (for file output type)")
    parser.add_argument("-m", "--mod", help="Modifier key for hotkey (ctrl, alt, shift, cmd)")
    parser.add_argument("-g", "--key", help="Key for hotkey (f1-f12, etc.)")
    parser.add_argument("-r", "--retries", type=int, default=3, help="Number of API retries on failure (default: 3)")
    args = parser.parse_args()
    
    # Set service type
    global g_service
    if args.service == "replicate":
        g_service = SERVICE_REPLICATE
    else:
        g_service = SERVICE_ELEVENLABS
        
    # Set API key from arguments or environment variable
    api_key = None
    if g_service == SERVICE_REPLICATE:
        api_key = args.api_key or os.environ.get("REPLICATE_API_TOKEN")
        if not api_key:
            print("Error: No Replicate API token provided. Set with --api-key or REPLICATE_API_TOKEN environment variable.")
            return 1
    else:  # SERVICE_ELEVENLABS
        api_key = args.api_key or os.environ.get("ELEVENLABS_API_KEY")
        if not api_key:
            print("Error: No ElevenLabs API key provided. Set with --api-key or ELEVENLABS_API_KEY environment variable.")
            return 1
    
    g_api_key = api_key
    
    # Get retry count
    max_retries = args.retries
    
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
    
    # Set up hotkey combination
    modifier_key = DEFAULT_MODIFIER
    main_key = DEFAULT_KEY
    
    # Map string modifier keys to keyboard.Key objects
    modifier_map = {
        "ctrl": keyboard.Key.ctrl, 
        "alt": keyboard.Key.alt, 
        "shift": keyboard.Key.shift, 
        "cmd": keyboard.Key.cmd,
        "meta": keyboard.Key.cmd
    }
    
    # Map string keys to keyboard.Key objects
    key_map = {
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
    
    # Set modifier key
    if args.mod and args.mod in modifier_map:
        modifier_key = modifier_map[args.mod]
    
    # Set main key
    if args.key:
        if args.key in key_map:
            main_key = key_map[args.key]
        elif len(args.key) == 1:
            # For regular keys (letters, numbers, etc.)
            main_key = keyboard.KeyCode.from_char(args.key)
    
    # Set up signal handler
    signal.signal(signal.SIGINT, signal_handler)
    
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
    
    # Start hotkey listener
    print(f"Setting up global hotkey: {modifier_key}+{main_key}")
    hotkey_listener = GlobalHotkeyListener(modifier_key, main_key)
    hotkey_listener.start()
    
    # Start input monitoring thread as fallback
    import select
    input_thread = threading.Thread(target=keyboard_input_monitor)
    input_thread.daemon = True
    input_thread.start()
    
    print(f"Whisper Dictation - Press the global hotkey or Enter to start/stop recording")
    
    if g_service == SERVICE_REPLICATE:
        print(f"Using Replicate API for transcription (Whisper v3 large turbo)")
    else:  # SERVICE_ELEVENLABS
        print(f"Using ElevenLabs API for transcription (model: {ELEVENLABS_MODEL})")
        
    print(f"Temporary audio files will be stored in {temp_dir}")
    print(f"API retries: {max_retries}")
    
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
                
                # Transcribe audio based on selected service
                transcription = None
                if g_service == SERVICE_REPLICATE:
                    print("Using Replicate API for transcription...")
                    transcription = transcribe_with_replicate(str(wav_path), max_retries=max_retries)
                else:  # SERVICE_ELEVENLABS
                    print("Using ElevenLabs API for transcription...")
                    transcription = transcribe_with_elevenlabs(str(wav_path), max_retries=max_retries)
                
                if transcription:
                    # Process output
                    process_output(transcription)
                else:
                    print("Failed to get transcription from the selected API.")
                
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
    import select
    sys.exit(main())
