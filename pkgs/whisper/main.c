#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <unistd.h>
#include <sys/stat.h>
#include <curl/curl.h>
#include <errno.h>
#include <pthread.h>
#include <fcntl.h>
#include <jansson.h>
#include <uiohook.h>

#ifdef __APPLE__
#include <ApplicationServices/ApplicationServices.h>
#elif defined(_WIN32)
#include <windows.h>
#else
#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/extensions/XTest.h>
#include <xdo.h>
#endif

#include "recording.h"

#define OPENAI_API_URL "https://api.openai.com/v1/audio/transcriptions"
#define OPENAI_API_MODEL "whisper-1"
#define OUTPUT_TO_CLIPBOARD 1
#define OUTPUT_TO_FILE 2
#define OUTPUT_TO_STDOUT 3
#define OUTPUT_TO_PASTE 4

// Default hotkey combination for starting/stopping recording
#define DEFAULT_MODIFIER_KEY (1 << 2) // CTRL key (1 is shift, 2 is ctrl, 3 is alt, 4 is meta)
#define DEFAULT_KEY VC_F12        // F12 key

// Hotkey configuration
static uint16_t hotkey_modifier = DEFAULT_MODIFIER_KEY;
static uint16_t hotkey_key = DEFAULT_KEY;

// Flags to indicate app state
static volatile int g_is_running = 1;
static volatile int g_is_recording = 0;
static volatile int g_toggle_recording = 0;
static pthread_t input_thread;

// Mutex for thread synchronization
static pthread_mutex_t g_mutex = PTHREAD_MUTEX_INITIALIZER;

// Output type and file path
static int g_output_type = OUTPUT_TO_STDOUT;
static char g_output_file[1024] = {0};

// OpenAI API key
static char g_api_key[256] = {0};

// Struct for memory buffer for curl responses
struct MemoryStruct {
    char *memory;
    size_t size;
};

// Structure to write received data to a file
struct download_data {
    FILE *fp;
    size_t bytes_downloaded;
    size_t last_report_bytes;
};

// Function to get the XDG cache directory
char* get_xdg_cache_dir() {
    char* xdg_cache_home = getenv("XDG_CACHE_HOME");
    
    if (xdg_cache_home != NULL && strlen(xdg_cache_home) > 0) {
        char* result = strdup(xdg_cache_home);
        return result;
    } else {
        char* home = getenv("HOME");
        if (home == NULL) {
            return NULL;
        }
        
        char* cache_dir = malloc(strlen(home) + 15); // Extra space for "/.cache/whisper"
        if (cache_dir == NULL) {
            return NULL;
        }
        
        sprintf(cache_dir, "%s/.cache", home);
        return cache_dir;
    }
}

// Callback function for writing downloaded data
size_t write_callback(void *ptr, size_t size, size_t nmemb, void *userdata) {
    struct download_data *data = (struct download_data*)userdata;
    size_t written = fwrite(ptr, size, nmemb, data->fp);
    data->bytes_downloaded += written * size;
    
    // Report progress every 5MB
    if (data->bytes_downloaded - data->last_report_bytes > 5 * 1024 * 1024) {
        printf("Downloaded %.1f MB...\n", (float)data->bytes_downloaded / (1024 * 1024));
        data->last_report_bytes = data->bytes_downloaded;
    }
    
    return written;
}

// Function to create directories recursively
int mkdir_recursive(const char *path) {
    char temp[1024];
    char *p = NULL;
    size_t len;
    
    snprintf(temp, sizeof(temp), "%s", path);
    len = strlen(temp);
    
    if (temp[len - 1] == '/') {
        temp[len - 1] = 0;
    }
    
    for (p = temp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            if (mkdir(temp, 0755) != 0) {
                if (errno != EEXIST) {
                    return -1;
                }
            }
            *p = '/';
        }
    }
    
    if (mkdir(temp, 0755) != 0) {
        if (errno != EEXIST) {
            return -1;
        }
    }
    
    return 0;
}

// Function to download the model
int download_model(const char *url, const char *output_path) {
    CURL *curl;
    CURLcode res;
    struct download_data data = {0};
    FILE *fp;
    
    curl_global_init(CURL_GLOBAL_DEFAULT);
    curl = curl_easy_init();
    
    if (!curl) {
        fprintf(stderr, "Error: Failed to initialize curl\n");
        return 1;
    }
    
    fp = fopen(output_path, "wb");
    if (!fp) {
        fprintf(stderr, "Error: Failed to open file for writing: %s\n", output_path);
        curl_easy_cleanup(curl);
        curl_global_cleanup();
        return 1;
    }
    
    data.fp = fp;
    data.bytes_downloaded = 0;
    data.last_report_bytes = 0;
    
    printf("Downloading model from %s\n", url);
    printf("This may take a while depending on your internet connection...\n");
    
    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_callback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &data);
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    
    res = curl_easy_perform(curl);
    
    fclose(fp);
    
    if (res != CURLE_OK) {
        fprintf(stderr, "Error: Failed to download file: %s\n", curl_easy_strerror(res));
        curl_easy_cleanup(curl);
        curl_global_cleanup();
        return 1;
    }
    
    printf("Download completed: %.1f MB\n", (float)data.bytes_downloaded / (1024 * 1024));
    
    curl_easy_cleanup(curl);
    curl_global_cleanup();
    
    return 0;
}

// Write text to clipboard (platform-specific implementations)
void write_to_clipboard(const char* text) {
#ifdef __APPLE__
    // macOS: Write to temporary file and use pbcopy
    FILE* temp = fopen("/tmp/whisper_clipboard.txt", "w");
    if (temp) {
        fputs(text, temp);
        fclose(temp);
        system("cat /tmp/whisper_clipboard.txt | pbcopy");
        remove("/tmp/whisper_clipboard.txt");
        printf("Text copied to clipboard (macOS)\n");
    }
#elif defined(_WIN32)
    // Windows: Write to file and use clip.exe
    FILE* temp = fopen("whisper_clipboard.txt", "w");
    if (temp) {
        fputs(text, temp);
        fclose(temp);
        system("type whisper_clipboard.txt | clip");
        remove("whisper_clipboard.txt");
        printf("Text copied to clipboard (Windows)\n");
    }
#else
    // Linux: Try different clipboard tools
    FILE* temp = fopen("/tmp/whisper_clipboard.txt", "w");
    if (temp) {
        fputs(text, temp);
        fclose(temp);
        
        // Try Klipper first
        if (system("which qdbus > /dev/null 2>&1") == 0) {
            char cmd[4096] = {0};
            snprintf(cmd, sizeof(cmd), "qdbus org.kde.klipper /klipper org.kde.klipper.klipper.setClipboardContents \"$(cat /tmp/whisper_clipboard.txt)\"");
            system(cmd);
            printf("Text copied to clipboard (Klipper)\n");
        } 
        // Try other clipboard tools if Klipper doesn't work
        else if (system("which xclip > /dev/null 2>&1") == 0) {
            system("cat /tmp/whisper_clipboard.txt | xclip -selection clipboard");
            printf("Text copied to clipboard (Linux/X11 - xclip)\n");
        } else if (system("which xsel > /dev/null 2>&1") == 0) {
            system("cat /tmp/whisper_clipboard.txt | xsel -ib");
            printf("Text copied to clipboard (Linux/X11 - xsel)\n");
        } else if (system("which wl-copy > /dev/null 2>&1") == 0) {
            system("cat /tmp/whisper_clipboard.txt | wl-copy");
            printf("Text copied to clipboard (Linux/Wayland)\n");
        } else {
            printf("No clipboard tool found. Text saved to /tmp/whisper_clipboard.txt\n");
            printf("Consider installing one of: qdbus (for Klipper), xclip, xsel, or wl-copy\n");
        }
        remove("/tmp/whisper_clipboard.txt");
    }
#endif
}

// Type text directly to the active application using platform-specific methods
void direct_type_text(const char* text) {
    if (!text || strlen(text) == 0) return;
    
    printf("Typing text: %s\n", text);

#ifdef __APPLE__
    // Create a string containing the text to paste
    CFStringRef stringRef = CFStringCreateWithCString(NULL, text, kCFStringEncodingUTF8);
    
    // First copy it to pasteboard
    PasteboardRef pasteboard;
    PasteboardCreate(kPasteboardClipboard, &pasteboard);
    PasteboardClear(pasteboard);
    PasteboardSynchronize(pasteboard);
    
    CFDataRef dataRef = CFStringCreateExternalRepresentation(NULL, stringRef, kCFStringEncodingUTF8, 0);
    PasteboardPutItemFlavor(pasteboard, (PasteboardItemID)1, CFSTR("public.utf8-plain-text"), dataRef, 0);
    
    CFRelease(dataRef);
    CFRelease(stringRef);
    CFRelease(pasteboard);
    
    // Now simulate Cmd+V to paste
    CGEventRef keyDown1 = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)55, true);  // Command down
    CGEventRef keyDown2 = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)9, true);   // V down
    CGEventRef keyUp2 = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)9, false);    // V up
    CGEventRef keyUp1 = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)55, false);   // Command up
    
    CGEventSetFlags(keyDown2, kCGEventFlagMaskCommand);
    CGEventSetFlags(keyUp2, kCGEventFlagMaskCommand);
    
    CGEventPost(kCGHIDEventTap, keyDown1);
    CGEventPost(kCGHIDEventTap, keyDown2);
    CGEventPost(kCGHIDEventTap, keyUp2);
    CGEventPost(kCGHIDEventTap, keyUp1);
    
    CFRelease(keyDown1);
    CFRelease(keyDown2);
    CFRelease(keyUp2);
    CFRelease(keyUp1);
    
    printf("Text pasted (macOS)\n");
    
#elif defined(_WIN32)
    // First copy to clipboard
    const size_t len = strlen(text) + 1;
    HGLOBAL hMem = GlobalAlloc(GMEM_MOVEABLE, len);
    memcpy(GlobalLock(hMem), text, len);
    GlobalUnlock(hMem);
    
    if (OpenClipboard(NULL)) {
        EmptyClipboard();
        SetClipboardData(CF_TEXT, hMem);
        CloseClipboard();
        
        // Simulate Ctrl+V
        INPUT inputs[4] = {0};
        
        // Ctrl down
        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].ki.wVk = VK_CONTROL;
        
        // V down
        inputs[1].type = INPUT_KEYBOARD;
        inputs[1].ki.wVk = 'V';
        
        // V up
        inputs[2].type = INPUT_KEYBOARD;
        inputs[2].ki.wVk = 'V';
        inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;
        
        // Ctrl up
        inputs[3].type = INPUT_KEYBOARD;
        inputs[3].ki.wVk = VK_CONTROL;
        inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;
        
        SendInput(4, inputs, sizeof(INPUT));
        
        printf("Text pasted (Windows)\n");
    } else {
        GlobalFree(hMem);
        printf("Failed to open clipboard\n");
    }
    
#else
    // Linux using xdotool
    
    // First copy to clipboard
    write_to_clipboard(text);
    
    // Static xdotool instance (create only once)
    static xdo_t* xdo = NULL;
    if (xdo == NULL) {
        xdo = xdo_new(NULL);
        if (xdo == NULL) {
            fprintf(stderr, "Error: Failed to initialize xdotool\n");
            return;
        }
    }
    
    // Wait a bit to ensure clipboard is ready
    usleep(100000);
    
    // Simulate Ctrl+V
    xdo_send_keysequence_window(xdo, CURRENTWINDOW, "ctrl+v", 0);
    
    printf("Text pasted (Linux)\n");
#endif
}

// Process the transcribed text
void process_output(const char* text) {
    if (!text || strlen(text) == 0) return;
    
    switch(g_output_type) {
        case OUTPUT_TO_CLIPBOARD:
            printf("Copying to clipboard: %s\n", text);
            write_to_clipboard(text);
            break;
            
        case OUTPUT_TO_PASTE:
            printf("Pasting to active window: %s\n", text);
            direct_type_text(text);
            break;
            
        case OUTPUT_TO_FILE:
            if (strlen(g_output_file) > 0) {
                printf("Writing to file: %s\n", g_output_file);
                FILE* f = fopen(g_output_file, "a");
                if (f) {
                    fputs(text, f);
                    fputs("\n", f);
                    fclose(f);
                } else {
                    fprintf(stderr, "Error: Could not open output file %s\n", g_output_file);
                }
            }
            break;
            
        case OUTPUT_TO_STDOUT:
        default:
            printf("Transcript: %s\n", text);
            break;
    }
}

// Global hotkey dispatcher
static void* dispatch_data = NULL;

// uiohook event callback
static void handle_event(uiohook_event * const event) {
    switch (event->type) {
        case EVENT_KEY_PRESSED:
            // Check if this is our hotkey
            if (event->data.keyboard.keycode == hotkey_key && 
                (event->mask & hotkey_modifier) == hotkey_modifier) {
                
                pthread_mutex_lock(&g_mutex);
                g_toggle_recording = 1;
                pthread_mutex_unlock(&g_mutex);
                
                // We need to prevent this hotkey from being passed to other applications
                // This is a bit of a hack but works in most cases
                event->reserved = 1;
            }
            break;
            
        default:
            break;
    }
}

// Function to initialize the hook
static int init_hotkeys() {
    hook_set_dispatch_proc(handle_event);
    
    // Start the hook
    int code = hook_run();
    if (code != UIOHOOK_SUCCESS) {
        fprintf(stderr, "Failed to initialize global hotkeys: %d\n", code);
        return -1;
    }
    
    return 0;
}

// Thread function to start the hook and keep it running
void* hotkey_thread(void* arg) {
    printf("Initializing global hotkeys...\n");
    
    if (init_hotkeys() != 0) {
        fprintf(stderr, "Failed to initialize global hotkeys.\n");
        return NULL;
    }
    
    // This thread will block in hook_run until interrupted
    return NULL;
}

// Thread function to monitor keyboard input from stdin
// This is a fallback if the global hotkey system doesn't work
void* input_monitor(void* arg) {
    printf("Press ENTER to toggle recording, or Ctrl+C to quit\n");
    printf("Global hotkey: Ctrl+F12\n");
    
    // Set stdin to non-blocking mode
    int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
    fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
    
    char c;
    while (g_is_running) {
        // Check for input
        if (read(STDIN_FILENO, &c, 1) == 1) {
            if (c == '\n') {
                pthread_mutex_lock(&g_mutex);
                g_toggle_recording = 1;
                pthread_mutex_unlock(&g_mutex);
            }
        }
        
        usleep(100000); // Check every 100ms
    }
    
    // Restore stdin to blocking mode
    fcntl(STDIN_FILENO, F_SETFL, flags);
    
    return NULL;
}

// Callback for writing memory from curl
static size_t WriteMemoryCallback(void *contents, size_t size, size_t nmemb, void *userp) {
    size_t realsize = size * nmemb;
    struct MemoryStruct *mem = (struct MemoryStruct *)userp;
    
    char *ptr = realloc(mem->memory, mem->size + realsize + 1);
    if (!ptr) {
        printf("Not enough memory (realloc returned NULL)\n");
        return 0;
    }
    
    mem->memory = ptr;
    memcpy(&(mem->memory[mem->size]), contents, realsize);
    mem->size += realsize;
    mem->memory[mem->size] = 0;
    
    return realsize;
}

// Function to transcribe audio using OpenAI API
char* transcribe_with_openai(const char* audio_file_path) {
    if (strlen(g_api_key) == 0) {
        fprintf(stderr, "Error: OpenAI API key not set. Use --api-key option.\n");
        return NULL;
    }
    
    CURL *curl;
    CURLcode res;
    struct curl_httppost *formpost = NULL;
    struct curl_httppost *lastptr = NULL;
    struct MemoryStruct chunk;
    
    chunk.memory = malloc(1);
    chunk.size = 0;
    
    // Initialize curl
    curl_global_init(CURL_GLOBAL_ALL);
    curl = curl_easy_init();
    
    if (!curl) {
        fprintf(stderr, "Error initializing curl\n");
        free(chunk.memory);
        return NULL;
    }
    
    // Set up the form
    curl_formadd(&formpost, &lastptr,
                 CURLFORM_COPYNAME, "file",
                 CURLFORM_FILE, audio_file_path,
                 CURLFORM_CONTENTTYPE, "audio/wav",
                 CURLFORM_END);
    
    curl_formadd(&formpost, &lastptr,
                 CURLFORM_COPYNAME, "model",
                 CURLFORM_COPYCONTENTS, OPENAI_API_MODEL,
                 CURLFORM_END);
    
    // Set URL and headers
    curl_easy_setopt(curl, CURLOPT_URL, OPENAI_API_URL);
    
    struct curl_slist *headers = NULL;
    char auth_header[300];
    snprintf(auth_header, sizeof(auth_header), "Authorization: Bearer %s", g_api_key);
    headers = curl_slist_append(headers, auth_header);
    headers = curl_slist_append(headers, "Content-Type: multipart/form-data");
    
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteMemoryCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)&chunk);
    curl_easy_setopt(curl, CURLOPT_HTTPPOST, formpost);
    
    printf("Sending audio to OpenAI API for transcription...\n");
    
    // Make the request
    res = curl_easy_perform(curl);
    
    if (res != CURLE_OK) {
        fprintf(stderr, "curl_easy_perform() failed: %s\n", curl_easy_strerror(res));
        free(chunk.memory);
        curl_easy_cleanup(curl);
        curl_formfree(formpost);
        curl_slist_free_all(headers);
        curl_global_cleanup();
        return NULL;
    }
    
    // Parse the JSON response
    char* result = NULL;
    json_error_t error;
    json_t *json = json_loads(chunk.memory, 0, &error);
    
    if (json) {
        json_t *text = json_object_get(json, "text");
        if (text && json_is_string(text)) {
            const char *text_value = json_string_value(text);
            result = strdup(text_value);
        } else {
            fprintf(stderr, "Error parsing API response: 'text' field not found or not a string\n");
            fprintf(stderr, "Response: %s\n", chunk.memory);
        }
        json_decref(json);
    } else {
        fprintf(stderr, "Error parsing API response as JSON: %s\n", error.text);
        fprintf(stderr, "Response: %s\n", chunk.memory);
    }
    
    // Clean up
    free(chunk.memory);
    curl_easy_cleanup(curl);
    curl_formfree(formpost);
    curl_slist_free_all(headers);
    curl_global_cleanup();
    
    return result;
}

void handle_signal(int signum) {
    if (signum == SIGINT) {
        printf("\nCaught SIGINT, stopping application...\n");
        g_is_running = 0;
    }
}

void print_usage(const char* program_name) {
    printf("Usage: %s [OPTIONS]\n\n", program_name);
    printf("Options:\n");
    printf("  -k, --api-key KEY    OpenAI API key (required for OpenAI API usage)\n");
    printf("  -o, --output TYPE    Output type: clipboard, paste, file, stdout (default: clipboard)\n");
    printf("  -f, --file PATH      Output file path (for file output type)\n");
    printf("  -m, --mod KEY        Modifier key for hotkey (shift, ctrl, alt, meta) (default: ctrl)\n");
    printf("  -g, --key KEY        Key for hotkey (f1-f12, etc.) (default: f12)\n");
    printf("  -h, --help           Display this help message\n\n");
    printf("Instructions:\n");
    printf("  1. Run the application with your OpenAI API key\n");
    printf("  2. Press the global hotkey (Ctrl+F12 by default) or ENTER to start recording\n");
    printf("  3. Press the global hotkey or ENTER again to stop recording and process speech\n");
    printf("  4. The transcription will be sent to the specified output (clipboard by default)\n");
    printf("  5. Press Ctrl+C to exit the application\n\n");
    printf("Note: OpenAI API usage is charged at $0.006 per minute of audio\n\n");
    printf("The 'paste' output type will directly paste text into the active window\n");
}

int main(int argc, char** argv) {
    const char* output_type_str = "clipboard";
    const char* output_file_path = NULL;
    const char* api_key = NULL;
    const char* hotkey_mod_str = "ctrl";
    const char* hotkey_key_str = "f12";
    pthread_t hotkey_thread_id;
    
    // Check for API key in environment variable
    char* env_api_key = getenv("OPENAI_API_KEY");
    if (env_api_key) {
        api_key = env_api_key;
    }
    
    // Parse command line arguments
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-k") == 0 || strcmp(argv[i], "--api-key") == 0) {
            if (i + 1 < argc) {
                api_key = argv[i + 1];
                i++;
            } else {
                fprintf(stderr, "Error: Missing API key after %s\n", argv[i]);
                print_usage(argv[0]);
                return 1;
            }
        } else if (strcmp(argv[i], "-o") == 0 || strcmp(argv[i], "--output") == 0) {
            if (i + 1 < argc) {
                output_type_str = argv[i + 1];
                i++;
            } else {
                fprintf(stderr, "Error: Missing output type after %s\n", argv[i]);
                print_usage(argv[0]);
                return 1;
            }
        } else if (strcmp(argv[i], "-f") == 0 || strcmp(argv[i], "--file") == 0) {
            if (i + 1 < argc) {
                output_file_path = argv[i + 1];
                i++;
            } else {
                fprintf(stderr, "Error: Missing file path after %s\n", argv[i]);
                print_usage(argv[0]);
                return 1;
            }
        } else if (strcmp(argv[i], "-m") == 0 || strcmp(argv[i], "--mod") == 0) {
            if (i + 1 < argc) {
                hotkey_mod_str = argv[i + 1];
                i++;
            } else {
                fprintf(stderr, "Error: Missing modifier key after %s\n", argv[i]);
                print_usage(argv[0]);
                return 1;
            }
        } else if (strcmp(argv[i], "-g") == 0 || strcmp(argv[i], "--key") == 0) {
            if (i + 1 < argc) {
                hotkey_key_str = argv[i + 1];
                i++;
            } else {
                fprintf(stderr, "Error: Missing key after %s\n", argv[i]);
                print_usage(argv[0]);
                return 1;
            }
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else {
            fprintf(stderr, "Error: Unknown option: %s\n", argv[i]);
            print_usage(argv[0]);
            return 1;
        }
    }
    
    // Store API key
    if (api_key) {
        strncpy(g_api_key, api_key, sizeof(g_api_key) - 1);
    } else {
        fprintf(stderr, "Warning: No OpenAI API key provided. Set with --api-key or OPENAI_API_KEY environment variable.\n");
        return 1;
    }
    
    // Set output type
    if (strcmp(output_type_str, "clipboard") == 0) {
        g_output_type = OUTPUT_TO_CLIPBOARD;
    } else if (strcmp(output_type_str, "paste") == 0) {
        g_output_type = OUTPUT_TO_PASTE;
    } else if (strcmp(output_type_str, "file") == 0) {
        g_output_type = OUTPUT_TO_FILE;
        if (output_file_path) {
            strncpy(g_output_file, output_file_path, sizeof(g_output_file) - 1);
        } else {
            fprintf(stderr, "Warning: No output file specified, defaulting to whisper_output.txt\n");
            strncpy(g_output_file, "whisper_output.txt", sizeof(g_output_file) - 1);
        }
    } else if (strcmp(output_type_str, "stdout") == 0) {
        g_output_type = OUTPUT_TO_STDOUT;
    } else {
        fprintf(stderr, "Error: Unknown output type: %s\n", output_type_str);
        print_usage(argv[0]);
        return 1;
    }
    
    // Configure hotkey modifier
    if (strcmp(hotkey_mod_str, "shift") == 0) {
        hotkey_modifier = 1 << 0; // SHIFT
    } else if (strcmp(hotkey_mod_str, "ctrl") == 0) {
        hotkey_modifier = 1 << 2; // CTRL
    } else if (strcmp(hotkey_mod_str, "alt") == 0) {
        hotkey_modifier = 1 << 3; // ALT
    } else if (strcmp(hotkey_mod_str, "meta") == 0 || strcmp(hotkey_mod_str, "super") == 0) {
        hotkey_modifier = 1 << 4; // META/SUPER
    } else {
        fprintf(stderr, "Warning: Unknown modifier key '%s', using CTRL\n", hotkey_mod_str);
        hotkey_modifier = 1 << 2; // CTRL
    }
    
    // Configure hotkey
    if (strcmp(hotkey_key_str, "f1") == 0) hotkey_key = VC_F1;
    else if (strcmp(hotkey_key_str, "f2") == 0) hotkey_key = VC_F2;
    else if (strcmp(hotkey_key_str, "f3") == 0) hotkey_key = VC_F3;
    else if (strcmp(hotkey_key_str, "f4") == 0) hotkey_key = VC_F4;
    else if (strcmp(hotkey_key_str, "f5") == 0) hotkey_key = VC_F5;
    else if (strcmp(hotkey_key_str, "f6") == 0) hotkey_key = VC_F6;
    else if (strcmp(hotkey_key_str, "f7") == 0) hotkey_key = VC_F7;
    else if (strcmp(hotkey_key_str, "f8") == 0) hotkey_key = VC_F8;
    else if (strcmp(hotkey_key_str, "f9") == 0) hotkey_key = VC_F9;
    else if (strcmp(hotkey_key_str, "f10") == 0) hotkey_key = VC_F10;
    else if (strcmp(hotkey_key_str, "f11") == 0) hotkey_key = VC_F11;
    else if (strcmp(hotkey_key_str, "f12") == 0) hotkey_key = VC_F12;
    else {
        fprintf(stderr, "Warning: Unknown key '%s', using F12\n", hotkey_key_str);
        hotkey_key = VC_F12;
    }
    
    // Initialize signal handler
    signal(SIGINT, handle_signal);
    
    // Start the global hotkey thread
    if (pthread_create(&hotkey_thread_id, NULL, hotkey_thread, NULL) != 0) {
        fprintf(stderr, "Warning: Failed to create global hotkey thread. Fallback to keyboard input only.\n");
    }
    
    // Start input monitoring thread (as fallback)
    if (pthread_create(&input_thread, NULL, input_monitor, NULL) != 0) {
        fprintf(stderr, "Error: Failed to create input monitor thread\n");
        return 1;
    }
    
    printf("Whisper Dictation - Press %s+%s or ENTER to start/stop recording, or Ctrl+C to quit\n",
           hotkey_mod_str, hotkey_key_str);
    
    // Create a temp directory for audio files
    char temp_dir[1024] = {0};
    char* xdg_runtime_dir = getenv("XDG_RUNTIME_DIR");
    if (xdg_runtime_dir) {
        snprintf(temp_dir, sizeof(temp_dir), "%s/whisper_dictation", xdg_runtime_dir);
    } else {
        snprintf(temp_dir, sizeof(temp_dir), "/tmp/whisper_dictation");
    }
    
    if (mkdir_recursive(temp_dir) != 0) {
        fprintf(stderr, "Error: Failed to create temporary directory: %s\n", temp_dir);
        return 1;
    }
    
    printf("Temporary audio files will be stored in %s\n", temp_dir);
    printf("Using OpenAI API for transcription (Whisper API).\n");

    // Initialize the recording context
    void* rec_ctx = recording_init(16000, 1); // 16kHz mono for Whisper
    if (rec_ctx == NULL) {
        fprintf(stderr, "Failed to initialize recording.\n");
        return 1;
    }

    // Main loop
    int active_recording = 0;
    char transcript_buffer[4096] = {0};

    while (g_is_running) {
        // Check if recording toggle requested
        pthread_mutex_lock(&g_mutex);
        int toggle_requested = g_toggle_recording;
        if (toggle_requested) {
            g_is_recording = !g_is_recording;
            g_toggle_recording = 0;
        }
        int should_record = g_is_recording;
        pthread_mutex_unlock(&g_mutex);
        
        // Start/stop recording based on toggle state
        if (should_record && !active_recording) {
            printf("Starting recording session...\n");
            if (recording_start(rec_ctx) != 0) {
                fprintf(stderr, "Failed to start recording.\n");
                break;
            }
            active_recording = 1;
            recording_clear_buffer(rec_ctx);
        } else if (!should_record && active_recording) {
            printf("Stopping recording session...\n");
            recording_stop(rec_ctx);
            active_recording = 0;
            
            // Process the recorded audio
            float* audio_buffer = NULL;
            int n_samples = recording_get_audio_data(rec_ctx, &audio_buffer);
            
            if (n_samples > 0 && audio_buffer != NULL) {
                // Save the audio to a WAV file for API processing
                char wav_path[1100] = {0};
                snprintf(wav_path, sizeof(wav_path), "%s/recording_%ld.wav", temp_dir, time(NULL));
                
                // Open WAV file for writing
                FILE* wav_file = fopen(wav_path, "wb");
                if (wav_file) {
                    // Write WAV header
                    // RIFF header
                    fwrite("RIFF", 1, 4, wav_file);
                    int filesize = 36 + n_samples * sizeof(short); // 16-bit samples
                    fwrite(&filesize, 4, 1, wav_file);
                    fwrite("WAVE", 1, 4, wav_file);
                    
                    // Format subchunk
                    fwrite("fmt ", 1, 4, wav_file);
                    int subchunk1size = 16;
                    fwrite(&subchunk1size, 4, 1, wav_file);
                    short audioformat = 1; // PCM
                    fwrite(&audioformat, 2, 1, wav_file);
                    short numchannels = 1; // Mono
                    fwrite(&numchannels, 2, 1, wav_file);
                    int samplerate = 16000;
                    fwrite(&samplerate, 4, 1, wav_file);
                    int byterate = samplerate * numchannels * sizeof(short);
                    fwrite(&byterate, 4, 1, wav_file);
                    short blockalign = numchannels * sizeof(short);
                    fwrite(&blockalign, 2, 1, wav_file);
                    short bitspersample = 16;
                    fwrite(&bitspersample, 2, 1, wav_file);
                    
                    // Data subchunk
                    fwrite("data", 1, 4, wav_file);
                    int subchunk2size = n_samples * sizeof(short);
                    fwrite(&subchunk2size, 4, 1, wav_file);
                    
                    // Convert float samples to 16-bit PCM
                    short* pcm_samples = (short*)malloc(n_samples * sizeof(short));
                    if (pcm_samples) {
                        for (int i = 0; i < n_samples; i++) {
                            float sample = audio_buffer[i];
                            // Clamp to -1.0 to 1.0
                            if (sample > 1.0f) sample = 1.0f;
                            if (sample < -1.0f) sample = -1.0f;
                            // Convert to 16-bit
                            pcm_samples[i] = (short)(sample * 32767.0f);
                        }
                        
                        // Write the PCM data
                        fwrite(pcm_samples, sizeof(short), n_samples, wav_file);
                        free(pcm_samples);
                    }
                    
                    fclose(wav_file);
                    
                    // Send the WAV file to OpenAI API
                    char* transcription = transcribe_with_openai(wav_path);
                    
                    if (transcription) {
                        strncpy(transcript_buffer, transcription, sizeof(transcript_buffer) - 1);
                        // Process the output based on output type
                        process_output(transcript_buffer);
                        free(transcription);
                    } else {
                        fprintf(stderr, "Failed to get transcription from OpenAI API.\n");
                    }
                    
                    // Remove the temporary WAV file
                    remove(wav_path);
                } else {
                    fprintf(stderr, "Failed to create WAV file for API processing.\n");
                }
                
                // Free the temporary audio buffer
                free(audio_buffer);
            }
        }
        
        // Sleep for a moment to reduce CPU usage
        Pa_Sleep(50);
    }

    // Cleanup
    if (active_recording) {
        recording_stop(rec_ctx);
    }
    
    recording_free(rec_ctx);
    
    // Clean up input thread
    pthread_cancel(input_thread);
    pthread_join(input_thread, NULL);
    
    // Clean up hotkey thread
    hook_stop();
    pthread_cancel(hotkey_thread_id);
    pthread_join(hotkey_thread_id, NULL);
    
    // Clean up temp directory
    rmdir(temp_dir);

    return 0;
}
