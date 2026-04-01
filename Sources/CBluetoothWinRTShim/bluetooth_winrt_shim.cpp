#include "bluetooth_winrt_shim.h"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#if defined(_WIN32) && __has_include(<winrt/base.h>) && __has_include(<winrt/Windows.Devices.Bluetooth.h>)

#include <winrt/base.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Storage.Streams.h>

namespace {

using namespace winrt;
using namespace Windows::Devices::Bluetooth;
using namespace Windows::Devices::Bluetooth::Advertisement;
using namespace Windows::Devices::Bluetooth::GenericAttributeProfile;
using namespace Windows::Devices::Enumeration;
using namespace Windows::Devices::Radios;
using namespace Windows::Storage::Streams;

struct characteristic_cache_entry {
    GattCharacteristic characteristic{nullptr};
    std::string service_uuid;
    std::string characteristic_uuid;
};

struct connected_device_entry {
    uint64_t address = 0;
    BluetoothLEDevice device{nullptr};
    std::map<std::string, GattDeviceService> services_by_uuid;
    std::map<std::string, characteristic_cache_entry> characteristics_by_key;
};

struct bluetooth_winrt_client_state {
    std::mutex mutex;
    std::map<std::string, connected_device_entry> connected_devices;
};

struct bluetooth_winrt_subscription_state {
    GattCharacteristic characteristic{nullptr};
    event_token token{};
    bluetooth_winrt_notification_callback_t callback = nullptr;
    void *context = nullptr;
    std::string peripheral_id;
    std::string service_uuid;
    std::string characteristic_uuid;
};

struct peripheral_summary {
    std::string id;
    std::string name;
    int rssi = -127;
    std::vector<std::string> service_uuids;
};

constexpr const char *kDeviceAddressProperty = "System.Devices.Aep.DeviceAddress";

void ensure_apartment() noexcept {
    static thread_local bool initialized = false;
    if (initialized) {
        return;
    }

    try {
        init_apartment(apartment_type::multi_threaded);
    } catch (...) {
    }
    initialized = true;
}

std::string uppercase(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char character) {
        return static_cast<char>(std::toupper(character));
    });
    return value;
}

std::string guid_to_string(guid const &value) {
    return uppercase(to_string(to_hstring(value)));
}

std::string normalize_address(std::string value) {
    std::string normalized;
    normalized.reserve(value.size());
    for (char character : value) {
        if (character == ':' || character == '-' || character == ' ') {
            continue;
        }
        normalized.push_back(static_cast<char>(std::toupper(static_cast<unsigned char>(character))));
    }
    return normalized;
}

std::string address_to_string(uint64_t address) {
    std::ostringstream stream;
    stream << std::uppercase << std::hex;
    stream.width(12);
    stream.fill('0');
    stream << address;
    return stream.str();
}

bool try_parse_address(std::string const &value, uint64_t &address) {
    std::string normalized = normalize_address(value);
    if (normalized.empty()) {
        return false;
    }

    try {
        address = std::stoull(normalized, nullptr, 16);
        return true;
    } catch (...) {
        return false;
    }
}

std::string json_escape(std::string const &value) {
    std::ostringstream stream;
    for (char character : value) {
        switch (character) {
        case '\\':
            stream << "\\\\";
            break;
        case '"':
            stream << "\\\"";
            break;
        case '\n':
            stream << "\\n";
            break;
        case '\r':
            stream << "\\r";
            break;
        case '\t':
            stream << "\\t";
            break;
        default:
            stream << character;
            break;
        }
    }
    return stream.str();
}

char *copy_string(std::string const &value) {
    char *buffer = static_cast<char *>(std::malloc(value.size() + 1));
    if (buffer == nullptr) {
        return nullptr;
    }
    std::memcpy(buffer, value.data(), value.size());
    buffer[value.size()] = '\0';
    return buffer;
}

uint8_t *copy_bytes(std::vector<uint8_t> const &value) {
    if (value.empty()) {
        return nullptr;
    }

    uint8_t *buffer = static_cast<uint8_t *>(std::malloc(value.size()));
    if (buffer == nullptr) {
        return nullptr;
    }
    std::memcpy(buffer, value.data(), value.size());
    return buffer;
}

std::string service_key(std::string const &peripheral_id, std::string const &service_uuid) {
    return peripheral_id + "|" + uppercase(service_uuid);
}

std::string characteristic_key(
    std::string const &peripheral_id,
    std::string const &service_uuid,
    std::string const &characteristic_uuid
) {
    return peripheral_id + "|" + uppercase(service_uuid) + "|" + uppercase(characteristic_uuid);
}

int characteristic_properties_mask(GattCharacteristicProperties properties) {
    int mask = 0;
    auto raw = static_cast<uint32_t>(properties);
    if ((raw & static_cast<uint32_t>(GattCharacteristicProperties::Read)) != 0) {
        mask |= 1 << 0;
    }
    if ((raw & static_cast<uint32_t>(GattCharacteristicProperties::Write)) != 0) {
        mask |= 1 << 1;
    }
    if ((raw & static_cast<uint32_t>(GattCharacteristicProperties::WriteWithoutResponse)) != 0) {
        mask |= 1 << 2;
    }
    if (
        (raw & static_cast<uint32_t>(GattCharacteristicProperties::Notify)) != 0 ||
        (raw & static_cast<uint32_t>(GattCharacteristicProperties::Indicate)) != 0
    ) {
        mask |= 1 << 3;
    }
    return mask;
}

std::vector<uint8_t> buffer_to_bytes(IBuffer const &buffer) {
    std::vector<uint8_t> bytes;
    if (!buffer) {
        return bytes;
    }

    DataReader reader = DataReader::FromBuffer(buffer);
    bytes.resize(reader.UnconsumedBufferLength());
    if (!bytes.empty()) {
        reader.ReadBytes(bytes);
    }
    return bytes;
}

GattDeviceServicesResult get_services_result(BluetoothLEDevice const &device) {
    GattDeviceServicesResult result = device.GetGattServicesAsync(BluetoothCacheMode::Uncached).get();
    if (result.Status() == GattCommunicationStatus::Success) {
        return result;
    }
    return device.GetGattServicesAsync(BluetoothCacheMode::Cached).get();
}

GattCharacteristicsResult get_characteristics_result(GattDeviceService const &service) {
    GattCharacteristicsResult result = service.GetCharacteristicsAsync(BluetoothCacheMode::Uncached).get();
    if (result.Status() == GattCommunicationStatus::Success) {
        return result;
    }
    return service.GetCharacteristicsAsync(BluetoothCacheMode::Cached).get();
}

void cache_services(bluetooth_winrt_client_state *state, std::string const &peripheral_id, connected_device_entry &entry) {
    entry.services_by_uuid.clear();
    GattDeviceServicesResult result = get_services_result(entry.device);
    if (result.Status() != GattCommunicationStatus::Success) {
        return;
    }

    for (GattDeviceService const &service : result.Services()) {
        entry.services_by_uuid.emplace(guid_to_string(service.Uuid()), service);
    }

    std::lock_guard<std::mutex> guard(state->mutex);
    state->connected_devices[peripheral_id].services_by_uuid = entry.services_by_uuid;
}

connected_device_entry *connected_device_for(bluetooth_winrt_client_state *state, std::string const &peripheral_id) {
    if (state == nullptr) {
        return nullptr;
    }

    std::lock_guard<std::mutex> guard(state->mutex);
    auto iterator = state->connected_devices.find(peripheral_id);
    if (iterator == state->connected_devices.end()) {
        return nullptr;
    }
    return &iterator->second;
}

GattDeviceService resolve_service(
    bluetooth_winrt_client_state *state,
    std::string const &peripheral_id,
    std::string const &service_uuid
) {
    auto *entry = connected_device_for(state, peripheral_id);
    if (entry == nullptr) {
        return nullptr;
    }

    std::string key = uppercase(service_uuid);
    auto cached = entry->services_by_uuid.find(key);
    if (cached != entry->services_by_uuid.end()) {
        return cached->second;
    }

    cache_services(state, peripheral_id, *entry);
    cached = entry->services_by_uuid.find(key);
    if (cached != entry->services_by_uuid.end()) {
        return cached->second;
    }

    return nullptr;
}

GattCharacteristic resolve_characteristic(
    bluetooth_winrt_client_state *state,
    std::string const &peripheral_id,
    std::string const &service_uuid,
    std::string const &characteristic_uuid
) {
    auto *entry = connected_device_for(state, peripheral_id);
    if (entry == nullptr) {
        return nullptr;
    }

    std::string key = characteristic_key(peripheral_id, service_uuid, characteristic_uuid);
    auto cached = entry->characteristics_by_key.find(key);
    if (cached != entry->characteristics_by_key.end()) {
        return cached->second.characteristic;
    }

    GattDeviceService service = resolve_service(state, peripheral_id, service_uuid);
    if (!service) {
        return nullptr;
    }

    GattCharacteristicsResult result = get_characteristics_result(service);
    if (result.Status() != GattCommunicationStatus::Success) {
        return nullptr;
    }

    for (GattCharacteristic const &characteristic : result.Characteristics()) {
        characteristic_cache_entry cache_entry = {
            characteristic,
            uppercase(service_uuid),
            guid_to_string(characteristic.Uuid()),
        };
        entry->characteristics_by_key.emplace(
            characteristic_key(peripheral_id, cache_entry.service_uuid, cache_entry.characteristic_uuid),
            cache_entry
        );
    }

    cached = entry->characteristics_by_key.find(key);
    if (cached != entry->characteristics_by_key.end()) {
        return cached->second.characteristic;
    }

    return nullptr;
}

std::string peripheral_to_json(peripheral_summary const &summary) {
    std::ostringstream stream;
    stream << "{\"id\":\"" << json_escape(summary.id) << "\",";
    stream << "\"name\":\"" << json_escape(summary.name) << "\",";
    stream << "\"rssi\":" << summary.rssi << ",";
    stream << "\"advertisedServiceUUIDs\":[";
    for (size_t index = 0; index < summary.service_uuids.size(); ++index) {
        if (index > 0) {
            stream << ",";
        }
        stream << "\"" << json_escape(summary.service_uuids[index]) << "\"";
    }
    stream << "]}";
    return stream.str();
}

std::string characteristics_to_json(
    std::string const &service_uuid,
    Windows::Foundation::Collections::IVectorView<GattCharacteristic> const &characteristics
) {
    std::ostringstream stream;
    stream << "[";
    for (uint32_t index = 0; index < characteristics.Size(); ++index) {
        if (index > 0) {
            stream << ",";
        }
        GattCharacteristic characteristic = characteristics.GetAt(index);
        stream << "{\"serviceUUID\":\"" << json_escape(uppercase(service_uuid)) << "\",";
        stream << "\"characteristicUUID\":\"" << json_escape(guid_to_string(characteristic.Uuid())) << "\",";
        stream << "\"properties\":" << characteristic_properties_mask(characteristic.CharacteristicProperties()) << "}";
    }
    stream << "]";
    return stream.str();
}

std::string services_to_json(Windows::Foundation::Collections::IVectorView<GattDeviceService> const &services) {
    std::ostringstream stream;
    stream << "[";
    for (uint32_t index = 0; index < services.Size(); ++index) {
        if (index > 0) {
            stream << ",";
        }
        stream << "\"" << json_escape(guid_to_string(services.GetAt(index).Uuid())) << "\"";
    }
    stream << "]";
    return stream.str();
}

void merge_paired_devices(std::map<std::string, peripheral_summary> &results) {
    auto properties = single_threaded_vector<hstring>();
    properties.Append(to_hstring(kDeviceAddressProperty));
    auto devices = DeviceInformation::FindAllAsync(BluetoothLEDevice::GetDeviceSelector(), properties).get();

    for (DeviceInformation const &device : devices) {
        auto property = device.Properties().TryLookup(to_hstring(kDeviceAddressProperty));
        if (!property) {
            continue;
        }

        auto propertyValue = unbox_value_or<hstring>(property, hstring());
        std::string address = normalize_address(to_string(propertyValue));
        if (address.empty()) {
            continue;
        }

        peripheral_summary summary;
        summary.id = address;
        std::string name = to_string(device.Name());
        summary.name = name.empty() ? ("BLE Device " + address.substr(address.length() > 4 ? address.length() - 4 : 0)) : name;

        auto existing = results.find(summary.id);
        if (existing != results.end()) {
            if (existing->second.name.empty()) {
                existing->second.name = summary.name;
            }
        } else {
            results.emplace(summary.id, summary);
        }
    }
}

} // namespace

extern "C" int32_t bluetooth_winrt_is_supported(void) {
    ensure_apartment();
    return 1;
}

extern "C" void *bluetooth_winrt_client_create(void) {
    ensure_apartment();
    return new bluetooth_winrt_client_state();
}

extern "C" void bluetooth_winrt_client_destroy(void *client) {
    delete reinterpret_cast<bluetooth_winrt_client_state *>(client);
}

extern "C" int32_t bluetooth_winrt_adapter_state(void) {
    ensure_apartment();

    try {
        BluetoothAdapter adapter = BluetoothAdapter::GetDefaultAsync().get();
        if (!adapter) {
            return 3;
        }

        try {
            Radio radio = adapter.GetRadioAsync().get();
            if (!radio) {
                return 2;
            }

            switch (radio.State()) {
            case RadioState::On:
                return 2;
            case RadioState::Off:
                return 1;
            case RadioState::Disabled:
                return 3;
            default:
                return 0;
            }
        } catch (...) {
            return 2;
        }
    } catch (...) {
        return 3;
    }
}

extern "C" char *bluetooth_winrt_scan_json(void *client, uint32_t timeout_ms) {
    ensure_apartment();
    if (client == nullptr) {
        return nullptr;
    }

    try {
        std::mutex results_mutex;
        std::map<std::string, peripheral_summary> results;
        BluetoothLEAdvertisementWatcher watcher;
        watcher.ScanningMode(BluetoothLEScanningMode::Active);

        auto token = watcher.Received([&](BluetoothLEAdvertisementWatcher const &, BluetoothLEAdvertisementReceivedEventArgs const &args) {
            peripheral_summary summary;
            summary.id = address_to_string(args.BluetoothAddress());
            std::string name = to_string(args.Advertisement().LocalName());
            summary.name = name.empty() ? ("BLE Device " + summary.id.substr(summary.id.length() > 4 ? summary.id.length() - 4 : 0)) : name;
            summary.rssi = args.RawSignalStrengthInDBm();
            for (guid const &service : args.Advertisement().ServiceUuids()) {
                summary.service_uuids.push_back(guid_to_string(service));
            }

            std::lock_guard<std::mutex> guard(results_mutex);
            auto existing = results.find(summary.id);
            if (existing == results.end()) {
                results.emplace(summary.id, summary);
            } else {
                if (existing->second.name.empty() && !summary.name.empty()) {
                    existing->second.name = summary.name;
                }
                existing->second.rssi = summary.rssi;
                for (std::string const &service : summary.service_uuids) {
                    if (std::find(existing->second.service_uuids.begin(), existing->second.service_uuids.end(), service) == existing->second.service_uuids.end()) {
                        existing->second.service_uuids.push_back(service);
                    }
                }
            }
        });

        watcher.Start();
        std::this_thread::sleep_for(std::chrono::milliseconds(timeout_ms > 0 ? timeout_ms : 1200));
        watcher.Stop();
        watcher.Received(token);

        {
            std::lock_guard<std::mutex> guard(results_mutex);
            merge_paired_devices(results);
        }

        std::vector<peripheral_summary> summaries;
        {
            std::lock_guard<std::mutex> guard(results_mutex);
            for (auto const &entry : results) {
                summaries.push_back(entry.second);
            }
        }

        std::sort(summaries.begin(), summaries.end(), [](peripheral_summary const &lhs, peripheral_summary const &rhs) {
            if (lhs.name == rhs.name) {
                return lhs.id < rhs.id;
            }
            return lhs.name < rhs.name;
        });

        std::ostringstream stream;
        stream << "[";
        for (size_t index = 0; index < summaries.size(); ++index) {
            if (index > 0) {
                stream << ",";
            }
            stream << peripheral_to_json(summaries[index]);
        }
        stream << "]";
        return copy_string(stream.str());
    } catch (...) {
        return nullptr;
    }
}

extern "C" int32_t bluetooth_winrt_connect(void *client, const char *peripheral_id) {
    ensure_apartment();
    if (client == nullptr || peripheral_id == nullptr) {
        return -1;
    }

    uint64_t address = 0;
    if (!try_parse_address(peripheral_id, address)) {
        return -1;
    }

    try {
        BluetoothLEDevice device = BluetoothLEDevice::FromBluetoothAddressAsync(address).get();
        if (!device) {
            return -1;
        }

        auto *state = reinterpret_cast<bluetooth_winrt_client_state *>(client);
        std::lock_guard<std::mutex> guard(state->mutex);
        connected_device_entry entry;
        entry.address = address;
        entry.device = device;
        state->connected_devices[uppercase(peripheral_id)] = entry;
        return 0;
    } catch (...) {
        return -1;
    }
}

extern "C" void bluetooth_winrt_disconnect(void *client, const char *peripheral_id) {
    if (client == nullptr || peripheral_id == nullptr) {
        return;
    }

    auto *state = reinterpret_cast<bluetooth_winrt_client_state *>(client);
    std::lock_guard<std::mutex> guard(state->mutex);
    state->connected_devices.erase(uppercase(peripheral_id));
}

extern "C" char *bluetooth_winrt_discover_services_json(void *client, const char *peripheral_id) {
    ensure_apartment();
    if (client == nullptr || peripheral_id == nullptr) {
        return nullptr;
    }

    try {
        auto *state = reinterpret_cast<bluetooth_winrt_client_state *>(client);
        auto *entry = connected_device_for(state, uppercase(peripheral_id));
        if (entry == nullptr) {
            return nullptr;
        }

        GattDeviceServicesResult result = get_services_result(entry->device);
        if (result.Status() != GattCommunicationStatus::Success) {
            return nullptr;
        }

        entry->services_by_uuid.clear();
        for (GattDeviceService const &service : result.Services()) {
            entry->services_by_uuid.emplace(guid_to_string(service.Uuid()), service);
        }

        return copy_string(services_to_json(result.Services()));
    } catch (...) {
        return nullptr;
    }
}

extern "C" char *bluetooth_winrt_discover_characteristics_json(
    void *client,
    const char *peripheral_id,
    const char *service_uuid
) {
    ensure_apartment();
    if (client == nullptr || peripheral_id == nullptr || service_uuid == nullptr) {
        return nullptr;
    }

    try {
        auto *state = reinterpret_cast<bluetooth_winrt_client_state *>(client);
        std::string peripheral_key = uppercase(peripheral_id);
        std::string service_key_value = uppercase(service_uuid);
        GattDeviceService service = resolve_service(state, peripheral_key, service_key_value);
        if (!service) {
            return nullptr;
        }

        GattCharacteristicsResult result = get_characteristics_result(service);
        if (result.Status() != GattCommunicationStatus::Success) {
            return nullptr;
        }

        if (auto *entry = connected_device_for(state, peripheral_key)) {
            for (GattCharacteristic const &characteristic : result.Characteristics()) {
                characteristic_cache_entry cache_entry = {
                    characteristic,
                    service_key_value,
                    guid_to_string(characteristic.Uuid()),
                };
                entry->characteristics_by_key[characteristic_key(peripheral_key, cache_entry.service_uuid, cache_entry.characteristic_uuid)] = cache_entry;
            }
        }

        return copy_string(characteristics_to_json(service_key_value, result.Characteristics()));
    } catch (...) {
        return nullptr;
    }
}

extern "C" int32_t bluetooth_winrt_read_value(
    void *client,
    const char *peripheral_id,
    const char *service_uuid,
    const char *characteristic_uuid,
    uint8_t **out_bytes,
    uint32_t *out_length
) {
    ensure_apartment();
    if (
        client == nullptr ||
        peripheral_id == nullptr ||
        service_uuid == nullptr ||
        characteristic_uuid == nullptr ||
        out_bytes == nullptr ||
        out_length == nullptr
    ) {
        return -1;
    }

    *out_bytes = nullptr;
    *out_length = 0;

    try {
        auto *state = reinterpret_cast<bluetooth_winrt_client_state *>(client);
        GattCharacteristic characteristic = resolve_characteristic(
            state,
            uppercase(peripheral_id),
            uppercase(service_uuid),
            uppercase(characteristic_uuid)
        );
        if (!characteristic) {
            return -1;
        }

        GattReadResult result = characteristic.ReadValueAsync(BluetoothCacheMode::Uncached).get();
        if (result.Status() != GattCommunicationStatus::Success) {
            result = characteristic.ReadValueAsync(BluetoothCacheMode::Cached).get();
        }
        if (result.Status() != GattCommunicationStatus::Success) {
            return -1;
        }

        std::vector<uint8_t> bytes = buffer_to_bytes(result.Value());
        *out_length = static_cast<uint32_t>(bytes.size());
        *out_bytes = copy_bytes(bytes);
        return 0;
    } catch (...) {
        return -1;
    }
}

extern "C" int32_t bluetooth_winrt_write_value(
    void *client,
    const char *peripheral_id,
    const char *service_uuid,
    const char *characteristic_uuid,
    const uint8_t *bytes,
    uint32_t length,
    int32_t write_mode
) {
    ensure_apartment();
    if (client == nullptr || peripheral_id == nullptr || service_uuid == nullptr || characteristic_uuid == nullptr) {
        return -1;
    }

    try {
        auto *state = reinterpret_cast<bluetooth_winrt_client_state *>(client);
        GattCharacteristic characteristic = resolve_characteristic(
            state,
            uppercase(peripheral_id),
            uppercase(service_uuid),
            uppercase(characteristic_uuid)
        );
        if (!characteristic) {
            return -1;
        }

        DataWriter writer;
        if (bytes != nullptr && length > 0) {
            std::vector<uint8_t> payload(bytes, bytes + length);
            writer.WriteBytes(array_view<const uint8_t>(payload));
        }

        auto option = write_mode == 0 ? GattWriteOption::WriteWithResponse : GattWriteOption::WriteWithoutResponse;
        GattCommunicationStatus status = characteristic.WriteValueAsync(writer.DetachBuffer(), option).get();
        return status == GattCommunicationStatus::Success ? 0 : -1;
    } catch (...) {
        return -1;
    }
}

extern "C" void *bluetooth_winrt_subscribe(
    void *client,
    const char *peripheral_id,
    const char *service_uuid,
    const char *characteristic_uuid,
    bluetooth_winrt_notification_callback_t callback,
    void *context
) {
    ensure_apartment();
    if (
        client == nullptr ||
        peripheral_id == nullptr ||
        service_uuid == nullptr ||
        characteristic_uuid == nullptr ||
        callback == nullptr
    ) {
        return nullptr;
    }

    try {
        auto *state = reinterpret_cast<bluetooth_winrt_client_state *>(client);
        std::string peripheral_key = uppercase(peripheral_id);
        std::string service_key_value = uppercase(service_uuid);
        std::string characteristic_key_value = uppercase(characteristic_uuid);
        GattCharacteristic characteristic = resolve_characteristic(state, peripheral_key, service_key_value, characteristic_key_value);
        if (!characteristic) {
            return nullptr;
        }

        auto properties = static_cast<uint32_t>(characteristic.CharacteristicProperties());
        GattClientCharacteristicConfigurationDescriptorValue descriptor_value;
        if ((properties & static_cast<uint32_t>(GattCharacteristicProperties::Notify)) != 0) {
            descriptor_value = GattClientCharacteristicConfigurationDescriptorValue::Notify;
        } else if ((properties & static_cast<uint32_t>(GattCharacteristicProperties::Indicate)) != 0) {
            descriptor_value = GattClientCharacteristicConfigurationDescriptorValue::Indicate;
        } else {
            return nullptr;
        }

        auto *subscription = new bluetooth_winrt_subscription_state();
        subscription->characteristic = characteristic;
        subscription->callback = callback;
        subscription->context = context;
        subscription->peripheral_id = peripheral_key;
        subscription->service_uuid = service_key_value;
        subscription->characteristic_uuid = characteristic_key_value;

        subscription->token = characteristic.ValueChanged([subscription](GattCharacteristic const &, GattValueChangedEventArgs const &args) {
            std::vector<uint8_t> payload = buffer_to_bytes(args.CharacteristicValue());
            subscription->callback(
                subscription->context,
                subscription->peripheral_id.c_str(),
                subscription->service_uuid.c_str(),
                subscription->characteristic_uuid.c_str(),
                payload.empty() ? nullptr : payload.data(),
                static_cast<uint32_t>(payload.size())
            );
        });

        GattCommunicationStatus status = characteristic.WriteClientCharacteristicConfigurationDescriptorAsync(descriptor_value).get();
        if (status != GattCommunicationStatus::Success) {
            characteristic.ValueChanged(subscription->token);
            delete subscription;
            return nullptr;
        }

        return subscription;
    } catch (...) {
        return nullptr;
    }
}

extern "C" void bluetooth_winrt_unsubscribe(void *client, void *subscription) {
    (void)client;
    if (subscription == nullptr) {
        return;
    }

    try {
        auto *state = reinterpret_cast<bluetooth_winrt_subscription_state *>(subscription);
        state->characteristic.ValueChanged(state->token);
        state->characteristic.WriteClientCharacteristicConfigurationDescriptorAsync(
            GattClientCharacteristicConfigurationDescriptorValue::None
        ).get();
        delete state;
    } catch (...) {
        delete reinterpret_cast<bluetooth_winrt_subscription_state *>(subscription);
    }
}

extern "C" void bluetooth_winrt_free_string(const char *value) {
    if (value != nullptr) {
        std::free(const_cast<char *>(value));
    }
}

extern "C" void bluetooth_winrt_free_bytes(uint8_t *bytes) {
    if (bytes != nullptr) {
        std::free(bytes);
    }
}

#else

extern "C" int32_t bluetooth_winrt_is_supported(void) {
    return 0;
}

extern "C" void *bluetooth_winrt_client_create(void) {
    return nullptr;
}

extern "C" void bluetooth_winrt_client_destroy(void *client) {
    (void)client;
}

extern "C" int32_t bluetooth_winrt_adapter_state(void) {
    return 3;
}

extern "C" char *bluetooth_winrt_scan_json(void *client, uint32_t timeout_ms) {
    (void)client;
    (void)timeout_ms;
    return nullptr;
}

extern "C" int32_t bluetooth_winrt_connect(void *client, const char *peripheral_id) {
    (void)client;
    (void)peripheral_id;
    return -1;
}

extern "C" void bluetooth_winrt_disconnect(void *client, const char *peripheral_id) {
    (void)client;
    (void)peripheral_id;
}

extern "C" char *bluetooth_winrt_discover_services_json(void *client, const char *peripheral_id) {
    (void)client;
    (void)peripheral_id;
    return nullptr;
}

extern "C" char *bluetooth_winrt_discover_characteristics_json(
    void *client,
    const char *peripheral_id,
    const char *service_uuid
) {
    (void)client;
    (void)peripheral_id;
    (void)service_uuid;
    return nullptr;
}

extern "C" int32_t bluetooth_winrt_read_value(
    void *client,
    const char *peripheral_id,
    const char *service_uuid,
    const char *characteristic_uuid,
    uint8_t **out_bytes,
    uint32_t *out_length
) {
    (void)client;
    (void)peripheral_id;
    (void)service_uuid;
    (void)characteristic_uuid;
    if (out_bytes != nullptr) {
        *out_bytes = nullptr;
    }
    if (out_length != nullptr) {
        *out_length = 0;
    }
    return -1;
}

extern "C" int32_t bluetooth_winrt_write_value(
    void *client,
    const char *peripheral_id,
    const char *service_uuid,
    const char *characteristic_uuid,
    const uint8_t *bytes,
    uint32_t length,
    int32_t write_mode
) {
    (void)client;
    (void)peripheral_id;
    (void)service_uuid;
    (void)characteristic_uuid;
    (void)bytes;
    (void)length;
    (void)write_mode;
    return -1;
}

extern "C" void *bluetooth_winrt_subscribe(
    void *client,
    const char *peripheral_id,
    const char *service_uuid,
    const char *characteristic_uuid,
    bluetooth_winrt_notification_callback_t callback,
    void *context
) {
    (void)client;
    (void)peripheral_id;
    (void)service_uuid;
    (void)characteristic_uuid;
    (void)callback;
    (void)context;
    return nullptr;
}

extern "C" void bluetooth_winrt_unsubscribe(void *client, void *subscription) {
    (void)client;
    (void)subscription;
}

extern "C" void bluetooth_winrt_free_string(const char *value) {
    if (value != nullptr) {
        std::free(const_cast<char *>(value));
    }
}

extern "C" void bluetooth_winrt_free_bytes(uint8_t *bytes) {
    if (bytes != nullptr) {
        std::free(bytes);
    }
}

#endif
