#include "recording.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_RECORDING_SECONDS 60
#define FRAMES_PER_BUFFER 1024

typedef struct {
    PaStream* stream;
    float* recorded_data;
    int recorded_frames;
    int max_frames;
    int channels;
    int sample_rate;
    PaStreamParameters input_params;
} recording_context;

// PortAudio callback function
static int pa_callback(const void* input_buffer, void* output_buffer,
                       unsigned long frames_per_buffer,
                       const PaStreamCallbackTimeInfo* time_info,
                       PaStreamCallbackFlags status_flags,
                       void* user_data) {
    recording_context* ctx = (recording_context*)user_data;
    const float* in = (const float*)input_buffer;
    
    // Check if we have space
    if (ctx->recorded_frames + frames_per_buffer <= ctx->max_frames) {
        // Copy the input data to our buffer
        memcpy(ctx->recorded_data + ctx->recorded_frames * ctx->channels,
               in, frames_per_buffer * ctx->channels * sizeof(float));
        ctx->recorded_frames += frames_per_buffer;
    }
    
    return paContinue;
}

void* recording_init(int sample_rate, int channels) {
    recording_context* ctx = (recording_context*)malloc(sizeof(recording_context));
    if (!ctx) return NULL;
    
    // Initialize PortAudio
    PaError err = Pa_Initialize();
    if (err != paNoError) {
        fprintf(stderr, "PortAudio error: %s\n", Pa_GetErrorText(err));
        free(ctx);
        return NULL;
    }
    
    // Set up context
    ctx->channels = channels;
    ctx->sample_rate = sample_rate;
    ctx->recorded_frames = 0;
    ctx->max_frames = sample_rate * MAX_RECORDING_SECONDS; // 60 seconds max
    
    // Allocate buffer for recorded data
    ctx->recorded_data = (float*)malloc(ctx->max_frames * channels * sizeof(float));
    if (!ctx->recorded_data) {
        Pa_Terminate();
        free(ctx);
        return NULL;
    }
    
    // Set up input parameters
    ctx->input_params.device = Pa_GetDefaultInputDevice();
    if (ctx->input_params.device == paNoDevice) {
        fprintf(stderr, "No default input device found.\n");
        Pa_Terminate();
        free(ctx->recorded_data);
        free(ctx);
        return NULL;
    }
    
    ctx->input_params.channelCount = channels;
    ctx->input_params.sampleFormat = paFloat32;
    ctx->input_params.suggestedLatency = Pa_GetDeviceInfo(ctx->input_params.device)->defaultLowInputLatency;
    ctx->input_params.hostApiSpecificStreamInfo = NULL;
    
    return ctx;
}

int recording_start(void* context) {
    recording_context* ctx = (recording_context*)context;
    
    // Open stream
    PaError err = Pa_OpenStream(&ctx->stream,
                                &ctx->input_params,
                                NULL, // No output
                                ctx->sample_rate,
                                FRAMES_PER_BUFFER,
                                paClipOff,
                                pa_callback,
                                ctx);
    
    if (err != paNoError) {
        fprintf(stderr, "PortAudio error: %s\n", Pa_GetErrorText(err));
        return -1;
    }
    
    // Start stream
    err = Pa_StartStream(ctx->stream);
    if (err != paNoError) {
        fprintf(stderr, "PortAudio error: %s\n", Pa_GetErrorText(err));
        Pa_CloseStream(ctx->stream);
        return -1;
    }
    
    return 0;
}

int recording_stop(void* context) {
    recording_context* ctx = (recording_context*)context;
    
    if (ctx->stream) {
        PaError err = Pa_StopStream(ctx->stream);
        if (err != paNoError) {
            fprintf(stderr, "PortAudio error: %s\n", Pa_GetErrorText(err));
            return -1;
        }
        
        err = Pa_CloseStream(ctx->stream);
        if (err != paNoError) {
            fprintf(stderr, "PortAudio error: %s\n", Pa_GetErrorText(err));
            return -1;
        }
        
        ctx->stream = NULL;
    }
    
    return 0;
}

void recording_free(void* context) {
    recording_context* ctx = (recording_context*)context;
    
    if (ctx) {
        if (ctx->stream) {
            recording_stop(ctx);
        }
        
        if (ctx->recorded_data) {
            free(ctx->recorded_data);
        }
        
        Pa_Terminate();
        free(ctx);
    }
}

int recording_get_buffer_size(void* context) {
    recording_context* ctx = (recording_context*)context;
    return ctx->recorded_frames;
}

int recording_get_audio_data(void* context, float** buffer) {
    recording_context* ctx = (recording_context*)context;
    
    if (ctx->recorded_frames == 0) {
        *buffer = NULL;
        return 0;
    }
    
    // Create a copy of the buffer
    float* new_buffer = (float*)malloc(ctx->recorded_frames * sizeof(float));
    if (!new_buffer) {
        *buffer = NULL;
        return 0;
    }
    
    // For Whisper, we need mono audio, so if we have stereo, convert to mono
    if (ctx->channels == 1) {
        memcpy(new_buffer, ctx->recorded_data, ctx->recorded_frames * sizeof(float));
    } else {
        // Convert to mono by averaging channels
        for (int i = 0; i < ctx->recorded_frames; i++) {
            float sum = 0;
            for (int c = 0; c < ctx->channels; c++) {
                sum += ctx->recorded_data[i * ctx->channels + c];
            }
            new_buffer[i] = sum / ctx->channels;
        }
    }
    
    *buffer = new_buffer;
    return ctx->recorded_frames;
}

void recording_clear_buffer(void* context) {
    recording_context* ctx = (recording_context*)context;
    ctx->recorded_frames = 0;
}