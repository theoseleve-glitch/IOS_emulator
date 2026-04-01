#ifndef BLUETOOTH_WINRT_SHIM_H
#define BLUETOOTH_WINRT_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*bluetooth_winrt_notification_callback_t)(
    void *context,
    const char *peripheral_id,
    const char *service_uuid,
    const char *characteristic_uuid,
    const uint8_t *bytes,
    uint32_t length
);

int32_t bluetooth_winrt_is_supported(void);
void *bluetooth_winrt_client_create(void);
void bluetooth_winrt_client_destroy(void *client);
int32_t bluetooth_winrt_adapter_state(void);
char *bluetooth_winrt_scan_json(void *client, uint32_t timeout_ms);
int32_t bluetooth_winrt_connect(void *client, const char *peripheral_id);
void bluetooth_winrt_disconnect(void *client, const char *peripheral_id);
char *bluetooth_winrt_discover_services_json(void *client, const char *peripheral_id);
char *bluetooth_winrt_discover_characteristics_json(
    void *client,
    const char *peripheral_id,
    const char *service_uuid
);
int32_t bluetooth_winrt_read_value(
    void *client,
    const char *peripheral_id,
    const char *service_uuid,
    const char *characteristic_uuid,
    uint8_t **out_bytes,
    uint32_t *out_length
);
int32_t bluetooth_winrt_write_value(
    void *client,
    const char *peripheral_id,
    const char *service_uuid,
    const char *characteristic_uuid,
    const uint8_t *bytes,
    uint32_t length,
    int32_t write_mode
);
void *bluetooth_winrt_subscribe(
    void *client,
    const char *peripheral_id,
    const char *service_uuid,
    const char *characteristic_uuid,
    bluetooth_winrt_notification_callback_t callback,
    void *context
);
void bluetooth_winrt_unsubscribe(void *client, void *subscription);
void bluetooth_winrt_free_string(const char *value);
void bluetooth_winrt_free_bytes(uint8_t *bytes);

#ifdef __cplusplus
}
#endif

#endif
