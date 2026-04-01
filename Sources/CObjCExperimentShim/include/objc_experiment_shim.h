#ifndef OBJC_EXPERIMENT_SHIM_H
#define OBJC_EXPERIMENT_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int objc_experiment_runtime_initialize(void);
int objc_experiment_configure_backend(const char *mode);
const char *objc_experiment_backend_name(void);
void *objc_experiment_register_selector(const char *name);
void *objc_experiment_register_sample_class(
    const char *name,
    void *selector,
    const char *response_text
);
void *objc_experiment_lookup_class(const char *name);
void *objc_experiment_create_instance(void *sample_class);
void *objc_experiment_retain_instance(void *instance);
void objc_experiment_release_instance(void *instance);
int objc_experiment_instance_responds_to_selector(void *instance, void *selector);
char *objc_experiment_instance_class_name(void *instance);
void *objc_experiment_autorelease_pool_push(void);
void objc_experiment_autorelease_pool_pop(void *pool);
char *objc_experiment_send_zero_arg_message(
    void *instance,
    void *selector
);
void objc_experiment_free_string(char *value);

#ifdef __cplusplus
}
#endif

#endif
