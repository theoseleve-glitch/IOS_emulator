#if defined(_WIN32)
#define _CRT_SECURE_NO_WARNINGS
#endif

#include "objc_experiment_shim.h"

#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#endif

typedef struct objc_experiment_selector objc_experiment_selector_t;
typedef struct objc_experiment_class objc_experiment_class_t;
typedef struct objc_experiment_instance objc_experiment_instance_t;

struct objc_experiment_selector {
    char *name;
};

struct objc_experiment_class {
    char *name;
    objc_experiment_selector_t *selector;
    char *response_text;
};

struct objc_experiment_instance {
    objc_experiment_class_t *sample_class;
    int32_t retain_count;
};

typedef enum objc_experiment_backend_kind {
    OBJC_EXPERIMENT_BACKEND_EMBEDDED = 0,
    OBJC_EXPERIMENT_BACKEND_LIBOBJC2 = 1,
} objc_experiment_backend_kind_t;

static int g_runtime_initialized = 0;
static const char *g_backend_name = "embedded-c-bridge";
static objc_experiment_backend_kind_t g_backend_kind = OBJC_EXPERIMENT_BACKEND_EMBEDDED;
static int g_backend_preference = -1;

static char *objc_experiment_duplicate_string(const char *value) {
    if (value == NULL) {
        return NULL;
    }

    size_t length = strlen(value) + 1;
    char *copy = (char *)malloc(length);
    if (copy == NULL) {
        return NULL;
    }

    memcpy(copy, value, length);
    return copy;
}

#if defined(_WIN32)
typedef void *(*objc_experiment_sel_register_name_fn)(const char *name);
typedef void *(*objc_experiment_objc_get_class_fn)(const char *name);
typedef void *(*objc_experiment_objc_allocate_class_pair_fn)(void *superclass, const char *name, size_t extraBytes);
typedef void (*objc_experiment_objc_register_class_pair_fn)(void *sample_class);
typedef int (*objc_experiment_class_add_method_fn)(void *sample_class, void *selector, void *implementation, const char *types);
typedef void *(*objc_experiment_class_create_instance_fn)(void *sample_class, size_t extraBytes);
typedef void *(*objc_experiment_objc_retain_fn)(void *instance);
typedef void (*objc_experiment_objc_release_fn)(void *instance);
typedef const char *(*objc_experiment_objc_msg_send_cstring_fn)(void *instance, void *selector);
typedef const char *(*objc_experiment_object_get_class_name_fn)(void *instance);

typedef struct objc_experiment_response_entry {
    char *class_name;
    char *response_text;
    struct objc_experiment_response_entry *next;
} objc_experiment_response_entry_t;

typedef struct objc_experiment_libobjc2_api {
    HMODULE module;
    objc_experiment_sel_register_name_fn sel_registerName;
    objc_experiment_objc_get_class_fn objc_getClass;
    objc_experiment_objc_allocate_class_pair_fn objc_allocateClassPair;
    objc_experiment_objc_register_class_pair_fn objc_registerClassPair;
    objc_experiment_class_add_method_fn class_addMethod;
    objc_experiment_class_create_instance_fn class_createInstance;
    objc_experiment_objc_retain_fn objc_retain;
    objc_experiment_objc_release_fn objc_release;
    objc_experiment_objc_msg_send_cstring_fn objc_msgSend_cstring;
    objc_experiment_object_get_class_name_fn object_getClassName;
} objc_experiment_libobjc2_api_t;

static objc_experiment_libobjc2_api_t g_libobjc2_api = {0};
static objc_experiment_response_entry_t *g_libobjc2_responses = NULL;

static void *objc_experiment_resolve_symbol(HMODULE module, const char *symbol) {
    if (module == NULL || symbol == NULL) {
        return NULL;
    }

    return (void *)GetProcAddress(module, symbol);
}

static void objc_experiment_reset_libobjc2_api(void) {
    if (g_libobjc2_api.module != NULL) {
        FreeLibrary(g_libobjc2_api.module);
    }

    memset(&g_libobjc2_api, 0, sizeof(g_libobjc2_api));
}

static int objc_experiment_try_load_libobjc2_from(const char *path) {
    HMODULE module;

    if (path == NULL || path[0] == '\0') {
        return 0;
    }

    module = LoadLibraryA(path);
    if (module == NULL) {
        return 0;
    }

    g_libobjc2_api.module = module;
    g_libobjc2_api.sel_registerName =
        (objc_experiment_sel_register_name_fn)objc_experiment_resolve_symbol(module, "sel_registerName");
    g_libobjc2_api.objc_getClass =
        (objc_experiment_objc_get_class_fn)objc_experiment_resolve_symbol(module, "objc_getClass");
    g_libobjc2_api.objc_allocateClassPair =
        (objc_experiment_objc_allocate_class_pair_fn)objc_experiment_resolve_symbol(module, "objc_allocateClassPair");
    g_libobjc2_api.objc_registerClassPair =
        (objc_experiment_objc_register_class_pair_fn)objc_experiment_resolve_symbol(module, "objc_registerClassPair");
    g_libobjc2_api.class_addMethod =
        (objc_experiment_class_add_method_fn)objc_experiment_resolve_symbol(module, "class_addMethod");
    g_libobjc2_api.class_createInstance =
        (objc_experiment_class_create_instance_fn)objc_experiment_resolve_symbol(module, "class_createInstance");
    g_libobjc2_api.objc_retain =
        (objc_experiment_objc_retain_fn)objc_experiment_resolve_symbol(module, "objc_retain");
    g_libobjc2_api.objc_release =
        (objc_experiment_objc_release_fn)objc_experiment_resolve_symbol(module, "objc_release");
    g_libobjc2_api.objc_msgSend_cstring =
        (objc_experiment_objc_msg_send_cstring_fn)objc_experiment_resolve_symbol(module, "objc_msgSend");
    g_libobjc2_api.object_getClassName =
        (objc_experiment_object_get_class_name_fn)objc_experiment_resolve_symbol(module, "object_getClassName");

    if (
        g_libobjc2_api.sel_registerName == NULL ||
        g_libobjc2_api.objc_getClass == NULL ||
        g_libobjc2_api.objc_allocateClassPair == NULL ||
        g_libobjc2_api.objc_registerClassPair == NULL ||
        g_libobjc2_api.class_addMethod == NULL ||
        g_libobjc2_api.class_createInstance == NULL ||
        g_libobjc2_api.objc_retain == NULL ||
        g_libobjc2_api.objc_release == NULL ||
        g_libobjc2_api.objc_msgSend_cstring == NULL ||
        g_libobjc2_api.object_getClassName == NULL
    ) {
        objc_experiment_reset_libobjc2_api();
        return 0;
    }

    return 1;
}

static int objc_experiment_try_initialize_libobjc2(void) {
    const char *explicit_path = getenv("LAP_LIBOBJC2_DLL");
    const char *explicit_root = getenv("IPHONE_EMULATOR_LIBOBJC2_BUILD");
    const char *host_arch = getenv("IPHONE_EMULATOR_HOST_ARCH");
    char explicit_candidate[MAX_PATH];
    char host_candidate[MAX_PATH];
    const char *relative_candidates[] = {
        "vendor\\libobjc2-build\\objc.dll",
        "vendor\\libobjc2-build-x64\\objc.dll",
        "vendor\\libobjc2-build-arm64\\objc.dll",
        ".\\vendor\\libobjc2-build\\objc.dll",
        ".\\vendor\\libobjc2-build-x64\\objc.dll",
        ".\\vendor\\libobjc2-build-arm64\\objc.dll",
        NULL,
    };
    size_t index = 0;

    if (objc_experiment_try_load_libobjc2_from(explicit_path)) {
        return 1;
    }

    if (explicit_root != NULL && explicit_root[0] != '\0') {
        snprintf(explicit_candidate, sizeof(explicit_candidate), "%s\\objc.dll", explicit_root);
        explicit_candidate[sizeof(explicit_candidate) - 1] = '\0';
        if (objc_experiment_try_load_libobjc2_from(explicit_candidate)) {
            return 1;
        }
    }

    if (host_arch != NULL && host_arch[0] != '\0') {
        snprintf(host_candidate, sizeof(host_candidate), "vendor\\libobjc2-build-%s\\objc.dll", host_arch);
        host_candidate[sizeof(host_candidate) - 1] = '\0';
        if (objc_experiment_try_load_libobjc2_from(host_candidate)) {
            return 1;
        }
    }

    while (relative_candidates[index] != NULL) {
        if (objc_experiment_try_load_libobjc2_from(relative_candidates[index])) {
            return 1;
        }
        index += 1;
    }

    return 0;
}

static objc_experiment_response_entry_t *objc_experiment_find_response_entry(const char *class_name) {
    objc_experiment_response_entry_t *entry = g_libobjc2_responses;

    while (entry != NULL) {
        if (class_name != NULL && strcmp(entry->class_name, class_name) == 0) {
            return entry;
        }
        entry = entry->next;
    }

    return NULL;
}

static int objc_experiment_set_response_text_for_class(const char *class_name, const char *response_text) {
    objc_experiment_response_entry_t *entry;
    char *response_copy;

    if (class_name == NULL || response_text == NULL) {
        return 0;
    }

    response_copy = objc_experiment_duplicate_string(response_text);
    if (response_copy == NULL) {
        return 0;
    }

    entry = objc_experiment_find_response_entry(class_name);
    if (entry != NULL) {
        free(entry->response_text);
        entry->response_text = response_copy;
        return 1;
    }

    entry = (objc_experiment_response_entry_t *)calloc(1, sizeof(objc_experiment_response_entry_t));
    if (entry == NULL) {
        free(response_copy);
        return 0;
    }

    entry->class_name = objc_experiment_duplicate_string(class_name);
    if (entry->class_name == NULL) {
        free(response_copy);
        free(entry);
        return 0;
    }

    entry->response_text = response_copy;
    entry->next = g_libobjc2_responses;
    g_libobjc2_responses = entry;
    return 1;
}

static const char *objc_experiment_libobjc2_zero_arg_method(void *self, void *_cmd) {
    const char *class_name;
    objc_experiment_response_entry_t *entry;

    (void)_cmd;

    if (self == NULL || g_libobjc2_api.object_getClassName == NULL) {
        return NULL;
    }

    class_name = g_libobjc2_api.object_getClassName(self);
    entry = objc_experiment_find_response_entry(class_name);

    return entry != NULL ? entry->response_text : NULL;
}
#endif

int objc_experiment_configure_backend(const char *mode) {
    if (mode == NULL || strcmp(mode, "auto") == 0) {
        if (g_runtime_initialized) {
            return 1;
        }
        g_backend_preference = -1;
        return 1;
    }
    if (strcmp(mode, "embedded") == 0) {
        if (g_runtime_initialized) {
            return g_backend_kind == OBJC_EXPERIMENT_BACKEND_EMBEDDED ? 1 : 0;
        }
        g_backend_preference = OBJC_EXPERIMENT_BACKEND_EMBEDDED;
        return 1;
    }
    if (strcmp(mode, "libobjc2") == 0) {
        if (g_runtime_initialized) {
            return g_backend_kind == OBJC_EXPERIMENT_BACKEND_LIBOBJC2 ? 1 : 0;
        }
        g_backend_preference = OBJC_EXPERIMENT_BACKEND_LIBOBJC2;
        return 1;
    }

    return 0;
}

int objc_experiment_runtime_initialize(void) {
    if (g_runtime_initialized) {
        return 0;
    }

#if defined(_WIN32)
    if (g_backend_preference != OBJC_EXPERIMENT_BACKEND_EMBEDDED && objc_experiment_try_initialize_libobjc2()) {
        g_backend_kind = OBJC_EXPERIMENT_BACKEND_LIBOBJC2;
        g_backend_name = "libobjc2-dynamic";
    } else if (g_backend_preference == OBJC_EXPERIMENT_BACKEND_LIBOBJC2) {
        return 1;
    }
#endif

    g_runtime_initialized = 1;
    return 0;
}

const char *objc_experiment_backend_name(void) {
    return g_backend_name;
}

void *objc_experiment_register_selector(const char *name) {
    if (!g_runtime_initialized || name == NULL) {
        return NULL;
    }

#if defined(_WIN32)
    if (g_backend_kind == OBJC_EXPERIMENT_BACKEND_LIBOBJC2) {
        return g_libobjc2_api.sel_registerName(name);
    }
#endif

    objc_experiment_selector_t *selector = (objc_experiment_selector_t *)calloc(1, sizeof(objc_experiment_selector_t));
    if (selector == NULL) {
        return NULL;
    }

    selector->name = objc_experiment_duplicate_string(name);
    if (selector->name == NULL) {
        free(selector);
        return NULL;
    }

    return selector;
}

void *objc_experiment_register_sample_class(
    const char *name,
    void *selector,
    const char *response_text
) {
#if defined(_WIN32)
    if (g_backend_kind == OBJC_EXPERIMENT_BACKEND_LIBOBJC2) {
        void *existing_class;
        void *sample_class;

        if (!g_runtime_initialized || name == NULL || selector == NULL || response_text == NULL) {
            return NULL;
        }

        existing_class = g_libobjc2_api.objc_getClass(name);
        if (existing_class != NULL) {
            return objc_experiment_set_response_text_for_class(name, response_text) ? existing_class : NULL;
        }

        sample_class = g_libobjc2_api.objc_allocateClassPair(NULL, name, 0);
        if (sample_class == NULL) {
            return NULL;
        }

        if (!g_libobjc2_api.class_addMethod(sample_class, selector, (void *)objc_experiment_libobjc2_zero_arg_method, "*@:")) {
            return NULL;
        }

        g_libobjc2_api.objc_registerClassPair(sample_class);
        return objc_experiment_set_response_text_for_class(name, response_text) ? sample_class : NULL;
    }
#endif

    objc_experiment_selector_t *typed_selector = (objc_experiment_selector_t *)selector;
    if (!g_runtime_initialized || name == NULL || typed_selector == NULL || response_text == NULL) {
        return NULL;
    }

    objc_experiment_class_t *sample_class = (objc_experiment_class_t *)calloc(1, sizeof(objc_experiment_class_t));
    if (sample_class == NULL) {
        return NULL;
    }

    sample_class->name = objc_experiment_duplicate_string(name);
    sample_class->response_text = objc_experiment_duplicate_string(response_text);
    sample_class->selector = typed_selector;

    if (sample_class->name == NULL || sample_class->response_text == NULL) {
        free(sample_class->name);
        free(sample_class->response_text);
        free(sample_class);
        return NULL;
    }

    return sample_class;
}

void *objc_experiment_lookup_class(const char *name) {
#if defined(_WIN32)
    if (g_backend_kind == OBJC_EXPERIMENT_BACKEND_LIBOBJC2) {
        if (!g_runtime_initialized || name == NULL) {
            return NULL;
        }
        return g_libobjc2_api.objc_getClass(name);
    }
#endif

    (void)name;
    return NULL;
}

void *objc_experiment_create_instance(void *sample_class) {
#if defined(_WIN32)
    if (g_backend_kind == OBJC_EXPERIMENT_BACKEND_LIBOBJC2) {
        if (!g_runtime_initialized || sample_class == NULL) {
            return NULL;
        }

        return g_libobjc2_api.class_createInstance(sample_class, 0);
    }
#endif

    objc_experiment_class_t *typed_class = (objc_experiment_class_t *)sample_class;
    if (!g_runtime_initialized || typed_class == NULL) {
        return NULL;
    }

    objc_experiment_instance_t *instance = (objc_experiment_instance_t *)calloc(1, sizeof(objc_experiment_instance_t));
    if (instance == NULL) {
        return NULL;
    }

    instance->sample_class = typed_class;
    instance->retain_count = 1;
    return instance;
}

void *objc_experiment_retain_instance(void *instance) {
#if defined(_WIN32)
    if (g_backend_kind == OBJC_EXPERIMENT_BACKEND_LIBOBJC2) {
        return instance != NULL ? g_libobjc2_api.objc_retain(instance) : NULL;
    }
#endif

    objc_experiment_instance_t *typed_instance = (objc_experiment_instance_t *)instance;
    if (typed_instance == NULL) {
        return NULL;
    }

    typed_instance->retain_count += 1;
    return typed_instance;
}

void objc_experiment_release_instance(void *instance) {
#if defined(_WIN32)
    if (g_backend_kind == OBJC_EXPERIMENT_BACKEND_LIBOBJC2) {
        if (instance != NULL) {
            g_libobjc2_api.objc_release(instance);
        }
        return;
    }
#endif

    objc_experiment_instance_t *typed_instance = (objc_experiment_instance_t *)instance;
    if (typed_instance == NULL) {
        return;
    }

    typed_instance->retain_count -= 1;
    if (typed_instance->retain_count <= 0) {
        free(typed_instance);
    }
}

int objc_experiment_instance_responds_to_selector(void *instance, void *selector) {
#if defined(_WIN32)
    if (g_backend_kind == OBJC_EXPERIMENT_BACKEND_LIBOBJC2) {
        char *response;
        if (instance == NULL || selector == NULL) {
            return 0;
        }
        response = objc_experiment_send_zero_arg_message(instance, selector);
        if (response == NULL) {
            return 0;
        }
        objc_experiment_free_string(response);
        return 1;
    }
#endif

    {
        objc_experiment_instance_t *typed_instance = (objc_experiment_instance_t *)instance;
        objc_experiment_selector_t *typed_selector = (objc_experiment_selector_t *)selector;
        if (
            typed_instance == NULL ||
            typed_selector == NULL ||
            typed_instance->sample_class == NULL ||
            typed_instance->sample_class->selector == NULL
        ) {
            return 0;
        }

        return strcmp(typed_instance->sample_class->selector->name, typed_selector->name) == 0 ? 1 : 0;
    }
}

char *objc_experiment_instance_class_name(void *instance) {
#if defined(_WIN32)
    if (g_backend_kind == OBJC_EXPERIMENT_BACKEND_LIBOBJC2) {
        const char *class_name;
        if (instance == NULL || g_libobjc2_api.object_getClassName == NULL) {
            return NULL;
        }
        class_name = g_libobjc2_api.object_getClassName(instance);
        return objc_experiment_duplicate_string(class_name);
    }
#endif

    {
        objc_experiment_instance_t *typed_instance = (objc_experiment_instance_t *)instance;
        if (typed_instance == NULL || typed_instance->sample_class == NULL) {
            return NULL;
        }
        return objc_experiment_duplicate_string(typed_instance->sample_class->name);
    }
}

void *objc_experiment_autorelease_pool_push(void) {
    if (!g_runtime_initialized) {
        return NULL;
    }

    return calloc(1, 1);
}

void objc_experiment_autorelease_pool_pop(void *pool) {
    free(pool);
}

char *objc_experiment_send_zero_arg_message(
    void *instance,
    void *selector
) {
#if defined(_WIN32)
    if (g_backend_kind == OBJC_EXPERIMENT_BACKEND_LIBOBJC2) {
        const char *response_text;

        if (instance == NULL || selector == NULL) {
            return NULL;
        }

        response_text = g_libobjc2_api.objc_msgSend_cstring(instance, selector);
        return objc_experiment_duplicate_string(response_text);
    }
#endif

    objc_experiment_instance_t *typed_instance = (objc_experiment_instance_t *)instance;
    objc_experiment_selector_t *typed_selector = (objc_experiment_selector_t *)selector;
    if (
        typed_instance == NULL ||
        typed_selector == NULL ||
        typed_instance->sample_class == NULL ||
        typed_instance->sample_class->selector == NULL
    ) {
        return NULL;
    }

    if (strcmp(typed_instance->sample_class->selector->name, typed_selector->name) != 0) {
        return NULL;
    }

    return objc_experiment_duplicate_string(typed_instance->sample_class->response_text);
}

void objc_experiment_free_string(char *value) {
    free(value);
}
