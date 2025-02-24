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

#include "recording.h"

#define OPENAI_API_URL "https://api.openai.com/v1/audio/transcriptions"
#define OPENAI_API_MODEL "whisper-1"
#define OUTPUT_TO_CLIPBOARD 1
#define OUTPUT_TO_FILE 2
#define OUTPUT_TO_STDOUT 3

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

// Process the transcribed text
void process_output(const char* text) {
    if (!text || strlen(text) == 0) return;
    
    switch(g_output_type) {
        case OUTPUT_TO_CLIPBOARD:
            printf("Copying to clipboard: %s\n", text);
            write_to_clipboard(text);
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

// Thread function to monitor keyboard input
void* input_monitor(void* arg) {
    printf("Press ENTER to toggle recording, or Ctrl+C to quit\n");
    
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
    printf("  -o, --output TYPE    Output type: clipboard, file, stdout (default: clipboard)\n");
    printf("  -f, --file PATH      Output file path (for file output type)\n");
    printf("  -h, --help           Display this help message\n\n");
    printf("Instructions:\n");
    printf("  1. Run the application with your OpenAI API key\n");
    printf("  2. Press ENTER to start recording\n");
    printf("  3. Press ENTER again to stop recording and process speech\n");
    printf("  4. The transcription will be sent to the specified output (clipboard by default)\n");
    printf("  5. Press Ctrl+C to exit the application\n\n");
    printf("Note: OpenAI API usage is charged at $0.006 per minute of audio\n\n");
}

int main(int argc, char** argv) {
    const char* output_type_str = "clipboard";
    const char* output_file_path = NULL;
    const char* api_key = NULL;
    
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
    
    // Initialize signal handler
    signal(SIGINT, handle_signal);
    
    // Start input monitoring thread
    if (pthread_create(&input_thread, NULL, input_monitor, NULL) != 0) {
        fprintf(stderr, "Error: Failed to create input monitor thread\n");
        return 1;
    }
    
    printf("Whisper Dictation - Press ENTER to start/stop recording, or Ctrl+C to quit\n");
    
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
    pthread_cancel(input_thread);
    pthread_join(input_thread, NULL);
    
    // Clean up temp directory
    rmdir(temp_dir);

    return 0;
}
