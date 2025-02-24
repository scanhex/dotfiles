#ifndef RECORDING_H
#define RECORDING_H

#include <portaudio.h>

// Initialize recording
void *recording_init(int sample_rate, int channels);

// Start recording
int recording_start(void *ctx);

// Stop recording
int recording_stop(void *ctx);

// Free recording resources
void recording_free(void *ctx);

// Get the current audio buffer size in samples
int recording_get_buffer_size(void *ctx);

// Get audio data from the buffer (caller must free the returned buffer)
int recording_get_audio_data(void *ctx, float **buffer);

// Clear the audio buffer
void recording_clear_buffer(void *ctx);

#endif // RECORDING_H