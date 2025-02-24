#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>

#include <whisper.h>
#include "recording.h"

// Flag to indicate if recording should stop
static volatile int g_is_running = 1;

void handle_signal(int signum) {
    if (signum == SIGINT) {
        printf("\nCaught SIGINT, stopping recording...\n");
        g_is_running = 0;
    }
}

int main(int argc, char** argv) {
    // Initialize signal handler
    signal(SIGINT, handle_signal);

    printf("Whisper Dictation - Press Ctrl+C to stop recording\n");

    // Initialize whisper parameters
    struct whisper_context_params cparams = whisper_context_default_params();
    
    // Initialize the whisper context
    struct whisper_context * ctx = whisper_init_from_file_with_params("models/ggml-base.en.bin", cparams);
    if (ctx == NULL) {
        fprintf(stderr, "Failed to initialize whisper context. Make sure the model is downloaded.\n");
        fprintf(stderr, "Run: wget -P models https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin\n");
        return 1;
    }

    // Initialize the recording context
    void* rec_ctx = recording_init(16000, 1); // 16kHz mono for Whisper
    if (rec_ctx == NULL) {
        fprintf(stderr, "Failed to initialize recording.\n");
        whisper_free(ctx);
        return 1;
    }

    printf("Starting recording...\n");
    if (recording_start(rec_ctx) != 0) {
        fprintf(stderr, "Failed to start recording.\n");
        recording_free(rec_ctx);
        whisper_free(ctx);
        return 1;
    }

    // Main loop
    while (g_is_running) {
        // Sleep for a moment to reduce CPU usage
        Pa_Sleep(100);

        // Check if we have enough audio to process
        if (recording_get_buffer_size(rec_ctx) >= 16000 * 3) { // 3 seconds of audio
            // Get the audio buffer
            float* audio_buffer = NULL;
            int n_samples = recording_get_audio_data(rec_ctx, &audio_buffer);
            
            if (n_samples > 0 && audio_buffer != NULL) {
                // Set up whisper parameters
                struct whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
                wparams.print_realtime = true;
                wparams.print_progress = false;
                wparams.translate = false;
                wparams.language = "en";
                wparams.n_threads = 4;
                
                // Run whisper on the audio buffer
                if (whisper_full(ctx, wparams, audio_buffer, n_samples) != 0) {
                    fprintf(stderr, "Failed to process audio with whisper.\n");
                } else {
                    // Get the number of segments
                    int n_segments = whisper_full_n_segments(ctx);
                    
                    // Print the transcript
                    for (int i = 0; i < n_segments; i++) {
                        const char* text = whisper_full_get_segment_text(ctx, i);
                        printf("%s", text);
                    }
                    printf("\n");
                    
                    // Clear the recording buffer for continuous recording
                    recording_clear_buffer(rec_ctx);
                }
                
                // Free the temporary audio buffer if needed
                free(audio_buffer);
            }
        }
    }

    // Cleanup
    printf("Stopping recording...\n");
    recording_stop(rec_ctx);
    recording_free(rec_ctx);
    whisper_free(ctx);

    return 0;
}