#include "runtime_shim.h"

#include <stdlib.h>
#include <string.h>

static runtime_shim_callback_t g_callback = NULL;
static void *g_context = NULL;

void runtime_shim_register_callback(runtime_shim_callback_t callback, void *context) {
    g_callback = callback;
    g_context = context;
}

void runtime_shim_clear_callback(void) {
    g_callback = NULL;
    g_context = NULL;
}

void runtime_shim_emit(const char *message) {
    if (g_callback != NULL) {
        g_callback(message, g_context);
    }
}

char *runtime_shim_roundtrip_string(const char *input) {
    if (input == NULL) {
        return NULL;
    }

    size_t length = strlen(input) + 1;
    char *buffer = (char *)malloc(length);

    if (buffer == NULL) {
        return NULL;
    }

    memcpy(buffer, input, length);
    return buffer;
}

uint8_t *runtime_shim_roundtrip_bytes(const uint8_t *input, size_t length, size_t *output_length) {
    if (output_length != NULL) {
        *output_length = length;
    }

    if (length == 0) {
        return NULL;
    }

    if (input == NULL) {
        if (output_length != NULL) {
            *output_length = 0;
        }
        return NULL;
    }

    uint8_t *buffer = (uint8_t *)malloc(length);

    if (buffer == NULL) {
        if (output_length != NULL) {
            *output_length = 0;
        }
        return NULL;
    }

    memcpy(buffer, input, length);
    return buffer;
}

void runtime_shim_free_string(char *value) {
    free(value);
}

void runtime_shim_free_bytes(uint8_t *value) {
    free(value);
}
