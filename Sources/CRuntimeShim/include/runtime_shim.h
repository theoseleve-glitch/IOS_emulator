#ifndef RUNTIME_SHIM_H
#define RUNTIME_SHIM_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*runtime_shim_callback_t)(const char *message, void *context);

void runtime_shim_register_callback(runtime_shim_callback_t callback, void *context);
void runtime_shim_clear_callback(void);
void runtime_shim_emit(const char *message);
char *runtime_shim_roundtrip_string(const char *input);
uint8_t *runtime_shim_roundtrip_bytes(const uint8_t *input, size_t length, size_t *output_length);
void runtime_shim_free_string(char *value);
void runtime_shim_free_bytes(uint8_t *value);

#ifdef __cplusplus
}
#endif

#endif
