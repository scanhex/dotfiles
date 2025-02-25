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

# Replicate API settings
REPLICATE_API_URL = "https://api.replicate.com/v1/predictions"
REPLICATE_MODEL_VERSION = "3ab86df6c8f54c11309d4d1f930ac292bad43ace52d10c80d87eb258b3c9f79c"

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
    """Global hotkey listener implementation"""
    
    def __init__(self, modifier_key, main_key):
        self.modifier_pressed = False
        self.modifier_key = modifier_key
        self.main_key = main_key
        self.listener = None
    
    def on_press(self, key):
        """Handle key press events"""
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
        """Handle key release events"""
        try:
            if key == self.modifier_key:
                self.modifier_pressed = False
        except Exception as e:
            print(f"Error in hotkey listener: {e}")
        
        return True  # Continue listening
    
    def start(self):
        """Start the keyboard listener"""
        self.listener = keyboard.Listener(on_press=self.on_press, on_release=self.on_release)
        self.listener.daemon = True
        self.listener.start()
    
    def stop(self):
        """Stop the keyboard listener"""
        if self.listener:
            self.listener.stop()


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
        if sys.platform == "darwin":  # macOS
            # Use AppleScript to type each character
            for char in text:
                # Escape special characters for AppleScript
                if char in ['"', '\\', "'", '`']:
                    char = f"\\{char}"
                
                cmd = f"""
                osascript -e 'tell application "System Events" to keystroke "{char}"'
                """
                os.system(cmd)
                # Small delay to prevent overwhelming the system
                time.sleep(0.01)
            return True
            
        elif sys.platform == "win32":  # Windows
            import ctypes
            from ctypes import wintypes
            
            # Load user32.dll
            user32 = ctypes.WinDLL('user32', use_last_error=True)
            
            # Constants
            INPUT_KEYBOARD = 1
            KEYEVENTF_UNICODE = 0x0004
            KEYEVENTF_KEYUP = 0x0002
            
            # Input structure for keyboard events
            class KEYBDINPUT(ctypes.Structure):
                _fields_ = (("wVk", wintypes.WORD),
                           ("wScan", wintypes.WORD),
                           ("dwFlags", wintypes.DWORD),
                           ("time", wintypes.DWORD),
                           ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)))
            
            class INPUT(ctypes.Structure):
                class _INPUT(ctypes.Union):
                    _fields_ = (("ki", KEYBDINPUT),
                               ("mi", ctypes.c_byte * 28),  # MouseInput
                               ("hi", ctypes.c_byte * 32))  # HardwareInput
                
                _anonymous_ = ("_input",)
                _fields_ = (("type", wintypes.DWORD),
                           ("_input", _INPUT))
            
            # Type each character
            for char in text:
                # Create keyboard input for the character
                unicode_val = ord(char)
                
                # Key down
                key_down = INPUT(type=INPUT_KEYBOARD,
                               ki=KEYBDINPUT(wVk=0, wScan=unicode_val, 
                                            dwFlags=KEYEVENTF_UNICODE, 
                                            time=0, dwExtraInfo=None))
                
                # Key up
                key_up = INPUT(type=INPUT_KEYBOARD,
                             ki=KEYBDINPUT(wVk=0, wScan=unicode_val, 
                                          dwFlags=KEYEVENTF_UNICODE | KEYEVENTF_KEYUP, 
                                          time=0, dwExtraInfo=None))
                
                # Send inputs
                inputs = (INPUT * 2)(key_down, key_up)
                user32.SendInput(2, ctypes.byref(inputs), ctypes.sizeof(INPUT))
                
                # Small delay to prevent overwhelming the system
                time.sleep(0.01)
            
            return True
            
        elif sys.platform.startswith("linux"):  # Linux
            try:
                # Use python-xlib for key simulation
                from Xlib import display, X
                from Xlib.protocol import event
                from Xlib.error import DisplayError
                from Xlib.XK import string_to_keysym
                
                # Get the display
                d = display.Display()
                
                # Get the active window (focus window)
                window = d.get_input_focus().focus
                
                # Helper function to send key event
                def send_key_event(keysym, press=True):
                    keycode = d.keysym_to_keycode(keysym)
                    if keycode == 0:
                        return False
                    
                    event_type = X.KeyPress if press else X.KeyRelease
                    key_event = event.KeyPress(
                        time=X.CurrentTime,
                        root=d.screen().root,
                        window=window,
                        same_screen=0, child=X.NONE,
                        root_x=0, root_y=0, event_x=0, event_y=0,
                        state=0,
                        detail=keycode
                    )
                    key_event.type = event_type
                    
                    window.send_event(key_event, propagate=True)
                    d.sync()
                    return True
                
                # Send each character
                for char in text:
                    # Map special characters
                    if char == ' ':
                        keysym = string_to_keysym("space")
                    elif char == '\n':
                        keysym = string_to_keysym("Return")
                    elif char == '\t':
                        keysym = string_to_keysym("Tab")
                    else:
                        keysym = string_to_keysym(char)
                    
                    # Press and release key
                    if keysym != 0:
                        send_key_event(keysym, True)  # Key press
                        send_key_event(keysym, False)  # Key release
                    
                    # Small delay
                    time.sleep(0.01)
                
                return True
                
            except (ImportError, DisplayError) as e:
                print(f"Cannot type character by character using Xlib: {e}")
                
                # Try pynput as fallback
                try:
                    from pynput.keyboard import Controller, Key
                    
                    keyboard = Controller()
                    
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
                        
                        # Small delay
                        time.sleep(0.01)
                    
                    return True
                    
                except Exception as e2:
                    print(f"Cannot type character by character using pynput: {e2}")
                    return False
                
        return False
    
    except Exception as e:
        print(f"Error typing text character by character: {e}")
        return False


def direct_type_text(text):
    """Type text directly to the active application"""
    if not text:
        return
    
    print(f"Typing text: {text}")
    
    # Check if current application is a text app
    is_text_app = is_text_application()
    print(f"Current application appears to be a text application: {is_text_app}")
    
    # Try to type character by character if it's a text app
    if is_text_app and type_text_char_by_char(text):
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


def transcribe_with_replicate(audio_file_path):
    """Transcribe audio using Replicate Whisper API"""
    global g_api_key
    
    if not g_api_key:
        print("Error: Replicate API token not set. Use --api-key option.")
        return None
    
    headers = {
        "Authorization": f"Bearer {g_api_key}",
        "Content-Type": "application/json",
        "Prefer": "wait"  # Wait for the prediction to complete
    }
    
    # First upload the file to Replicate
    with open(audio_file_path, "rb") as f:
        # Convert audio to base64 (suitable for small files)
        import base64
        audio_content = f.read()
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
    
    print("Sending audio to Replicate API for transcription...")
    
    try:
        response = requests.post(
            REPLICATE_API_URL,
            headers=headers,
            json=data
        )
        
        response.raise_for_status()
        result = response.json()
        
        # Check if the prediction completed successfully
        if result.get("status") == "succeeded":
            # The output format depends on the model, but assuming it's returned as text
            transcription = result.get("output", "")
            if isinstance(transcription, list) and transcription:
                return transcription[0]  # Often the first element contains the text
            return transcription
        else:
            print(f"Error: Prediction failed or timed out: {result}")
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
    global g_api_key, g_output_type, g_output_file, g_is_running, g_is_recording, g_toggle_recording, g_mutex
    
    # Set up argument parser
    parser = argparse.ArgumentParser(description="Whisper Dictation - A lightweight dictation app using Replicate's Whisper v3")
    parser.add_argument("-k", "--api-key", help="Replicate API token")
    parser.add_argument("-o", "--output", choices=["clipboard", "paste", "file", "stdout"], default="clipboard", 
                      help="Output type (paste will use character-by-character input for text applications)")
    parser.add_argument("-f", "--file", help="Output file path (for file output type)")
    parser.add_argument("-m", "--mod", help="Modifier key for hotkey (ctrl, alt, shift, cmd)")
    parser.add_argument("-g", "--key", help="Key for hotkey (f1-f12, etc.)")
    args = parser.parse_args()
    
    # Set API key from arguments or environment variable
    api_key = args.api_key or os.environ.get("REPLICATE_API_TOKEN")
    if api_key:
        g_api_key = api_key
    else:
        print("Error: No Replicate API token provided. Set with --api-key or REPLICATE_API_TOKEN environment variable.")
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
    print(f"Using Replicate API for transcription (Whisper v3 large turbo)")
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
                transcription = transcribe_with_replicate(str(wav_path))
                
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
    import select
    sys.exit(main())
