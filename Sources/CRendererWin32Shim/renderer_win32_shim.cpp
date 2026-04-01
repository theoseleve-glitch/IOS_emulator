#include "renderer_win32_shim.h"

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <windowsx.h>
#include <d2d1.h>
#include <dwrite.h>
#include <wincodec.h>

#include <algorithm>
#include <cmath>
#include <map>
#include <string>

namespace {

constexpr UINT WM_RENDERER_REDRAW = WM_APP + 42;
constexpr UINT TIMER_AUTOCLOSE = 1;
constexpr UINT TIMER_SCRIPTED_CLICK = 2;
constexpr UINT TIMER_LONG_PRESS = 3;
constexpr double DRAG_THRESHOLD = 8.0;
constexpr double SWIPE_THRESHOLD = 42.0;
constexpr ULONGLONG SWIPE_MAX_DURATION_MS = 650;
constexpr UINT LONG_PRESS_DELAY_MS = 550;

struct renderer_window_state_t {
    renderer_win32_callbacks_t callbacks;
    renderer_win32_snapshot_t *snapshot;
    ID2D1Factory *d2d_factory;
    IDWriteFactory *dwrite_factory;
    IWICImagingFactory *wic_factory;
    ID2D1HwndRenderTarget *render_target;
    ID2D1SolidColorBrush *brush;
    renderer_win32_run_report_t *report;
    int32_t auto_close_ms;
    int32_t scripted_action_delay_ms;
    int32_t frame_count;
    bool scripted_action_requested;
    bool scripted_action_dispatched;
    std::string scripted_action;
    std::map<std::string, ID2D1Bitmap *> image_cache;

    bool pointer_down;
    bool drag_started;
    bool long_press_dispatched;
    renderer_win32_point_t pointer_down_point;
    renderer_win32_point_t last_pointer_point;
    ULONGLONG pointer_down_timestamp_ms;
    std::string active_gesture_surface;
};

void safe_release(IUnknown **object) {
    if (object != nullptr && *object != nullptr) {
        (*object)->Release();
        *object = nullptr;
    }
}

ULONGLONG current_timestamp_ms() {
    return GetTickCount64();
}

std::wstring utf8_to_utf16(renderer_win32_string_t value) {
    if (value.data == nullptr || value.length == 0) {
        return std::wstring();
    }

    int required = MultiByteToWideChar(CP_UTF8, 0, value.data, static_cast<int>(value.length), nullptr, 0);
    if (required <= 0) {
        return std::wstring();
    }

    std::wstring result(static_cast<size_t>(required), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, value.data, static_cast<int>(value.length), &result[0], required);
    return result;
}

std::string utf8_to_string(renderer_win32_string_t value) {
    if (value.data == nullptr || value.length == 0) {
        return std::string();
    }

    return std::string(value.data, value.data + value.length);
}

renderer_win32_string_t string_to_utf8_view(const std::string &value) {
    return renderer_win32_string_t { value.c_str(), static_cast<uint32_t>(value.size()) };
}

D2D1_COLOR_F make_color(renderer_win32_color_t color) {
    return D2D1::ColorF(
        static_cast<FLOAT>(color.red),
        static_cast<FLOAT>(color.green),
        static_cast<FLOAT>(color.blue),
        static_cast<FLOAT>(color.alpha)
    );
}

D2D1_RECT_F make_rect(renderer_win32_rect_t rect) {
    return D2D1::RectF(
        static_cast<FLOAT>(rect.x),
        static_cast<FLOAT>(rect.y),
        static_cast<FLOAT>(rect.x + rect.width),
        static_cast<FLOAT>(rect.y + rect.height)
    );
}

D2D1_ROUNDED_RECT make_rounded_rect(renderer_win32_rect_t rect, double radius) {
    return D2D1::RoundedRect(make_rect(rect), static_cast<FLOAT>(radius), static_cast<FLOAT>(radius));
}

bool point_in_rect(renderer_win32_point_t point, renderer_win32_rect_t rect) {
    return point.x >= rect.x &&
        point.x <= rect.x + rect.width &&
        point.y >= rect.y &&
        point.y <= rect.y + rect.height;
}

double distance_between(renderer_win32_point_t lhs, renderer_win32_point_t rhs) {
    const double dx = lhs.x - rhs.x;
    const double dy = lhs.y - rhs.y;
    return std::sqrt((dx * dx) + (dy * dy));
}

int32_t current_modifier_mask() {
    int32_t modifiers = 0;
    if ((GetKeyState(VK_SHIFT) & 0x8000) != 0) {
        modifiers |= 1;
    }
    if ((GetKeyState(VK_CONTROL) & 0x8000) != 0) {
        modifiers |= 2;
    }
    if ((GetKeyState(VK_MENU) & 0x8000) != 0) {
        modifiers |= 4;
    }
    return modifiers;
}

const renderer_win32_focus_region_t *hit_test_focus_region(
    const renderer_win32_snapshot_t *snapshot,
    renderer_win32_point_t point
) {
    if (snapshot == nullptr || snapshot->focus_regions == nullptr) {
        return nullptr;
    }

    for (int index = static_cast<int>(snapshot->focus_region_count) - 1; index >= 0; --index) {
        const renderer_win32_focus_region_t *region = &snapshot->focus_regions[index];
        if (point_in_rect(point, region->rect)) {
            return region;
        }
    }

    return nullptr;
}

const renderer_win32_focus_region_t *focused_region(
    const renderer_win32_snapshot_t *snapshot,
    int32_t kind
) {
    if (snapshot == nullptr || snapshot->focus_regions == nullptr) {
        return nullptr;
    }

    for (uint32_t index = 0; index < snapshot->focus_region_count; ++index) {
        const renderer_win32_focus_region_t *region = &snapshot->focus_regions[index];
        if (region->kind == kind && region->is_focused != 0) {
            return region;
        }
    }

    return nullptr;
}

void release_snapshot(renderer_window_state_t *state) {
    if (state == nullptr || state->snapshot == nullptr) {
        return;
    }

    if (state->callbacks.release_frame != nullptr) {
        state->callbacks.release_frame(state->callbacks.context, state->snapshot);
    }

    state->snapshot = nullptr;
}

HRESULT ensure_factories(renderer_window_state_t *state) {
    HRESULT hr = S_OK;

    if (state->d2d_factory == nullptr) {
        hr = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, &state->d2d_factory);
        if (FAILED(hr)) {
            return hr;
        }
    }

    if (state->dwrite_factory == nullptr) {
        hr = DWriteCreateFactory(
            DWRITE_FACTORY_TYPE_SHARED,
            __uuidof(IDWriteFactory),
            reinterpret_cast<IUnknown **>(&state->dwrite_factory)
        );
        if (FAILED(hr)) {
            return hr;
        }
    }

    if (state->wic_factory == nullptr) {
        hr = CoCreateInstance(
            CLSID_WICImagingFactory,
            nullptr,
            CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&state->wic_factory)
        );
    }

    return hr;
}

void discard_device_resources(renderer_window_state_t *state) {
    if (state != nullptr) {
        for (auto &entry : state->image_cache) {
            safe_release(reinterpret_cast<IUnknown **>(&entry.second));
        }
        state->image_cache.clear();
    }
    safe_release(reinterpret_cast<IUnknown **>(&state->brush));
    safe_release(reinterpret_cast<IUnknown **>(&state->render_target));
}

HRESULT ensure_render_target(renderer_window_state_t *state, HWND hwnd) {
    HRESULT hr = ensure_factories(state);
    if (FAILED(hr)) {
        return hr;
    }

    if (state->render_target != nullptr) {
        return S_OK;
    }

    RECT client_rect = {0};
    GetClientRect(hwnd, &client_rect);
    D2D1_SIZE_U target_size = D2D1::SizeU(
        std::max<LONG>(1, client_rect.right - client_rect.left),
        std::max<LONG>(1, client_rect.bottom - client_rect.top)
    );

    hr = state->d2d_factory->CreateHwndRenderTarget(
        D2D1::RenderTargetProperties(),
        D2D1::HwndRenderTargetProperties(hwnd, target_size),
        &state->render_target
    );
    if (FAILED(hr)) {
        return hr;
    }

    return state->render_target->CreateSolidColorBrush(D2D1::ColorF(0, 0, 0, 1), &state->brush);
}

ID2D1Bitmap *load_bitmap(renderer_window_state_t *state, renderer_win32_string_t path) {
    if (
        state == nullptr ||
        state->render_target == nullptr ||
        state->wic_factory == nullptr ||
        path.data == nullptr ||
        path.length == 0
    ) {
        return nullptr;
    }

    const std::string key = utf8_to_string(path);
    const auto existing = state->image_cache.find(key);
    if (existing != state->image_cache.end()) {
        return existing->second;
    }

    const std::wstring wide_path = utf8_to_utf16(path);
    if (wide_path.empty()) {
        return nullptr;
    }

    IWICBitmapDecoder *decoder = nullptr;
    IWICBitmapFrameDecode *frame = nullptr;
    IWICFormatConverter *converter = nullptr;
    ID2D1Bitmap *bitmap = nullptr;

    HRESULT hr = state->wic_factory->CreateDecoderFromFilename(
        wide_path.c_str(),
        nullptr,
        GENERIC_READ,
        WICDecodeMetadataCacheOnLoad,
        &decoder
    );
    if (SUCCEEDED(hr)) {
        hr = decoder->GetFrame(0, &frame);
    }
    if (SUCCEEDED(hr)) {
        hr = state->wic_factory->CreateFormatConverter(&converter);
    }
    if (SUCCEEDED(hr)) {
        hr = converter->Initialize(
            frame,
            GUID_WICPixelFormat32bppPBGRA,
            WICBitmapDitherTypeNone,
            nullptr,
            0.0f,
            WICBitmapPaletteTypeMedianCut
        );
    }
    if (SUCCEEDED(hr)) {
        hr = state->render_target->CreateBitmapFromWicBitmap(converter, nullptr, &bitmap);
    }

    safe_release(reinterpret_cast<IUnknown **>(&converter));
    safe_release(reinterpret_cast<IUnknown **>(&frame));
    safe_release(reinterpret_cast<IUnknown **>(&decoder));

    if (FAILED(hr) || bitmap == nullptr) {
        safe_release(reinterpret_cast<IUnknown **>(&bitmap));
        return nullptr;
    }

    state->image_cache.insert(std::make_pair(key, bitmap));
    return bitmap;
}

void request_snapshot(renderer_window_state_t *state, HWND hwnd) {
    if (state == nullptr || state->callbacks.make_frame == nullptr) {
        return;
    }

    RECT client_rect = {0};
    GetClientRect(hwnd, &client_rect);
    const int32_t width = std::max<LONG>(1, client_rect.right - client_rect.left);
    const int32_t height = std::max<LONG>(1, client_rect.bottom - client_rect.top);

    release_snapshot(state);
    state->snapshot = state->callbacks.make_frame(state->callbacks.context, width, height);
    if (state->snapshot != nullptr) {
        state->frame_count += 1;
    }

    if (state->snapshot != nullptr) {
        const std::wstring title = utf8_to_utf16(state->snapshot->title);
        if (!title.empty()) {
            SetWindowTextW(hwnd, title.c_str());
        }
    }
}

IDWriteTextFormat *create_text_format(renderer_window_state_t *state, renderer_win32_text_style_t style) {
    if (state == nullptr || state->dwrite_factory == nullptr) {
        return nullptr;
    }

    std::wstring family = utf8_to_utf16(style.font_family);
    if (family.empty()) {
        family = L"Segoe UI";
    }

    IDWriteTextFormat *format = nullptr;
    HRESULT hr = state->dwrite_factory->CreateTextFormat(
        family.c_str(),
        nullptr,
        static_cast<DWRITE_FONT_WEIGHT>(style.font_weight),
        DWRITE_FONT_STYLE_NORMAL,
        DWRITE_FONT_STRETCH_NORMAL,
        static_cast<FLOAT>(style.font_size),
        L"en-us",
        &format
    );
    if (FAILED(hr) || format == nullptr) {
        return nullptr;
    }

    switch (style.horizontal_alignment) {
    case 1:
        format->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER);
        break;
    case 2:
        format->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_TRAILING);
        break;
    default:
        format->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_LEADING);
        break;
    }

    format->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_NEAR);
    return format;
}

void draw_command(renderer_window_state_t *state, const renderer_win32_command_t *command) {
    if (state == nullptr || command == nullptr || state->render_target == nullptr || state->brush == nullptr) {
        return;
    }

    switch (command->kind) {
    case RENDERER_WIN32_COMMAND_FILL:
        state->brush->SetColor(make_color(command->color));
        if (command->corner_radius > 0.0) {
            const D2D1_ROUNDED_RECT rounded = make_rounded_rect(command->rect, command->corner_radius);
            state->render_target->FillRoundedRectangle(rounded, state->brush);
        } else {
            state->render_target->FillRectangle(make_rect(command->rect), state->brush);
        }
        break;
    case RENDERER_WIN32_COMMAND_STROKE:
        state->brush->SetColor(make_color(command->color));
        if (command->corner_radius > 0.0) {
            const D2D1_ROUNDED_RECT rounded = make_rounded_rect(command->rect, command->corner_radius);
            state->render_target->DrawRoundedRectangle(rounded, state->brush, static_cast<FLOAT>(command->line_width));
        } else {
            state->render_target->DrawRectangle(make_rect(command->rect), state->brush, static_cast<FLOAT>(command->line_width));
        }
        break;
    case RENDERER_WIN32_COMMAND_LINE:
        state->brush->SetColor(make_color(command->color));
        state->render_target->DrawLine(
            D2D1::Point2F(static_cast<FLOAT>(command->from_point.x), static_cast<FLOAT>(command->from_point.y)),
            D2D1::Point2F(static_cast<FLOAT>(command->to_point.x), static_cast<FLOAT>(command->to_point.y)),
            state->brush,
            static_cast<FLOAT>(command->line_width)
        );
        break;
    case RENDERER_WIN32_COMMAND_TEXT: {
        IDWriteTextFormat *format = create_text_format(state, command->text_style);
        if (format == nullptr) {
            break;
        }
        const std::wstring value = utf8_to_utf16(command->text);
        state->brush->SetColor(make_color(command->text_style.color));
        state->render_target->DrawText(
            value.c_str(),
            static_cast<UINT32>(value.length()),
            format,
            make_rect(command->rect),
            state->brush
        );
        format->Release();
        break;
    }
    case RENDERER_WIN32_COMMAND_IMAGE: {
        ID2D1Bitmap *bitmap = load_bitmap(state, command->image_path);
        if (bitmap == nullptr) {
            state->brush->SetColor(D2D1::ColorF(0.18f, 0.20f, 0.28f, 1.0f));
            state->render_target->FillRectangle(make_rect(command->rect), state->brush);
            state->brush->SetColor(D2D1::ColorF(0.72f, 0.76f, 0.84f, 1.0f));
            state->render_target->DrawRectangle(make_rect(command->rect), state->brush, 1.0f);
            break;
        }
        state->render_target->DrawBitmap(
            bitmap,
            make_rect(command->rect),
            1.0f,
            D2D1_BITMAP_INTERPOLATION_MODE_LINEAR
        );
        break;
    }
    default:
        break;
    }
}

void refresh_after_handled(renderer_window_state_t *state, HWND hwnd) {
    request_snapshot(state, hwnd);
    InvalidateRect(hwnd, nullptr, FALSE);
}

void handle_action(renderer_window_state_t *state, HWND hwnd, renderer_win32_string_t action) {
    if (state == nullptr || state->callbacks.on_action == nullptr) {
        return;
    }

    state->callbacks.on_action(state->callbacks.context, action);
    refresh_after_handled(state, hwnd);
}

bool handle_input(renderer_window_state_t *state, HWND hwnd, int32_t input_event) {
    if (state == nullptr || state->callbacks.on_input == nullptr) {
        return false;
    }

    if (state->callbacks.on_input(state->callbacks.context, input_event) != 0) {
        refresh_after_handled(state, hwnd);
        return true;
    }

    return false;
}

bool handle_text_input(renderer_window_state_t *state, HWND hwnd, renderer_win32_text_input_t input_event) {
    if (state == nullptr || state->callbacks.on_text_input == nullptr) {
        return false;
    }

    if (state->callbacks.on_text_input(state->callbacks.context, input_event) != 0) {
        refresh_after_handled(state, hwnd);
        return true;
    }

    return false;
}

bool handle_pointer(renderer_window_state_t *state, HWND hwnd, renderer_win32_pointer_event_t pointer_event) {
    if (state == nullptr || state->callbacks.on_pointer == nullptr) {
        return false;
    }

    if (state->callbacks.on_pointer(state->callbacks.context, pointer_event) != 0) {
        refresh_after_handled(state, hwnd);
        return true;
    }

    return false;
}

bool handle_gesture(renderer_window_state_t *state, HWND hwnd, renderer_win32_gesture_event_t gesture_event) {
    if (state == nullptr || state->callbacks.on_gesture == nullptr) {
        return false;
    }

    if (state->callbacks.on_gesture(state->callbacks.context, gesture_event) != 0) {
        refresh_after_handled(state, hwnd);
        return true;
    }

    return false;
}

std::string target_identifier_for_point(renderer_window_state_t *state, renderer_win32_point_t point, int32_t *kind_out) {
    if (state == nullptr || state->snapshot == nullptr) {
        if (kind_out != nullptr) {
            *kind_out = -1;
        }
        return std::string();
    }

    if (const renderer_win32_focus_region_t *region = hit_test_focus_region(state->snapshot, point)) {
        if (kind_out != nullptr) {
            *kind_out = region->kind;
        }
        return utf8_to_string(region->identifier);
    }

    if (const renderer_win32_focus_region_t *focused = focused_region(state->snapshot, RENDERER_WIN32_FOCUS_GESTURE_SURFACE)) {
        if (kind_out != nullptr) {
            *kind_out = focused->kind;
        }
        return utf8_to_string(focused->identifier);
    }

    if (state->snapshot->focus_regions != nullptr) {
        for (uint32_t index = 0; index < state->snapshot->focus_region_count; ++index) {
            const renderer_win32_focus_region_t *region = &state->snapshot->focus_regions[index];
            if (region->kind == RENDERER_WIN32_FOCUS_GESTURE_SURFACE) {
                if (kind_out != nullptr) {
                    *kind_out = region->kind;
                }
                return utf8_to_string(region->identifier);
            }
        }
    }

    if (kind_out != nullptr) {
        *kind_out = -1;
    }
    return std::string();
}

void dispatch_pointer_event(renderer_window_state_t *state, HWND hwnd, int32_t phase, renderer_win32_point_t point) {
    int32_t target_kind = -1;
    const std::string target_identifier = target_identifier_for_point(state, point, &target_kind);
    const renderer_win32_pointer_event_t event = {
        phase,
        point.x,
        point.y,
        current_modifier_mask(),
        target_kind,
        string_to_utf8_view(target_identifier),
        static_cast<int64_t>(current_timestamp_ms()),
    };
    (void)handle_pointer(state, hwnd, event);
}

void dispatch_drag_gesture(
    renderer_window_state_t *state,
    HWND hwnd,
    int32_t kind,
    const std::string &surface_id,
    renderer_win32_point_t start_point,
    renderer_win32_point_t current_point
) {
    const renderer_win32_gesture_event_t event = {
        kind,
        string_to_utf8_view(surface_id),
        start_point.x,
        start_point.y,
        current_point.x,
        current_point.y,
        0.0,
        0,
        static_cast<int64_t>(current_timestamp_ms()),
    };
    (void)handle_gesture(state, hwnd, event);
}

void dispatch_long_press(renderer_window_state_t *state, HWND hwnd) {
    if (
        state == nullptr ||
        !state->pointer_down ||
        state->active_gesture_surface.empty() ||
        state->drag_started ||
        state->long_press_dispatched
    ) {
        return;
    }

    state->long_press_dispatched = true;
    const renderer_win32_gesture_event_t event = {
        RENDERER_WIN32_GESTURE_LONG_PRESS,
        string_to_utf8_view(state->active_gesture_surface),
        state->pointer_down_point.x,
        state->pointer_down_point.y,
        state->last_pointer_point.x,
        state->last_pointer_point.y,
        0.0,
        0,
        static_cast<int64_t>(current_timestamp_ms()),
    };
    (void)handle_gesture(state, hwnd, event);
}

void maybe_dispatch_swipe(renderer_window_state_t *state, HWND hwnd, renderer_win32_point_t release_point) {
    if (state == nullptr || state->active_gesture_surface.empty()) {
        return;
    }

    const ULONGLONG duration = current_timestamp_ms() - state->pointer_down_timestamp_ms;
    const double dx = release_point.x - state->pointer_down_point.x;
    const double dy = release_point.y - state->pointer_down_point.y;
    if (duration > SWIPE_MAX_DURATION_MS || std::max(std::abs(dx), std::abs(dy)) < SWIPE_THRESHOLD) {
        return;
    }

    int32_t direction = 0;
    if (std::abs(dx) >= std::abs(dy)) {
        direction = dx >= 0 ? 1 : 2;
    } else {
        direction = dy >= 0 ? 3 : 4;
    }

    const renderer_win32_gesture_event_t event = {
        RENDERER_WIN32_GESTURE_SWIPE,
        string_to_utf8_view(state->active_gesture_surface),
        state->pointer_down_point.x,
        state->pointer_down_point.y,
        release_point.x,
        release_point.y,
        0.0,
        direction,
        static_cast<int64_t>(current_timestamp_ms()),
    };
    (void)handle_gesture(state, hwnd, event);
}

void dispatch_scripted_click(renderer_window_state_t *state, HWND hwnd) {
    if (
        state == nullptr ||
        !state->scripted_action_requested ||
        state->scripted_action_dispatched ||
        state->snapshot == nullptr
    ) {
        return;
    }

    for (int index = static_cast<int>(state->snapshot->interaction_count) - 1; index >= 0; --index) {
        const renderer_win32_interaction_t *interaction = &state->snapshot->interactions[index];
        if (utf8_to_string(interaction->action) == state->scripted_action) {
            const LONG x = static_cast<LONG>(interaction->rect.x + (interaction->rect.width / 2.0));
            const LONG y = static_cast<LONG>(interaction->rect.y + (interaction->rect.height / 2.0));
            const LPARAM location = MAKELPARAM(x, y);
            state->scripted_action_dispatched = true;
            SendMessageW(hwnd, WM_LBUTTONDOWN, MK_LBUTTON, location);
            SendMessageW(hwnd, WM_LBUTTONUP, 0, location);
            return;
        }
    }
}

bool handle_text_keydown(renderer_window_state_t *state, HWND hwnd, WPARAM w_param) {
    if (state == nullptr || state->snapshot == nullptr) {
        return false;
    }

    const renderer_win32_focus_region_t *focused = focused_region(state->snapshot, RENDERER_WIN32_FOCUS_TEXT_FIELD);
    if (focused == nullptr) {
        return false;
    }

    renderer_win32_text_input_t text_event = {
        -1,
        focused->identifier,
        renderer_win32_string_t { nullptr, 0 },
    };

    switch (w_param) {
    case VK_BACK:
        text_event.kind = RENDERER_WIN32_TEXT_DELETE_BACKWARD;
        break;
    case VK_DELETE:
        text_event.kind = RENDERER_WIN32_TEXT_DELETE_FORWARD;
        break;
    case VK_LEFT:
        text_event.kind = RENDERER_WIN32_TEXT_MOVE_CARET_LEFT;
        break;
    case VK_RIGHT:
        text_event.kind = RENDERER_WIN32_TEXT_MOVE_CARET_RIGHT;
        break;
    case VK_HOME:
        text_event.kind = RENDERER_WIN32_TEXT_MOVE_CARET_TO_START;
        break;
    case VK_END:
        text_event.kind = RENDERER_WIN32_TEXT_MOVE_CARET_TO_END;
        break;
    case VK_RETURN:
        text_event.kind = RENDERER_WIN32_TEXT_SUBMIT;
        break;
    default:
        return false;
    }

    return handle_text_input(state, hwnd, text_event);
}

LRESULT CALLBACK renderer_window_proc(HWND hwnd, UINT message, WPARAM w_param, LPARAM l_param) {
    renderer_window_state_t *state = reinterpret_cast<renderer_window_state_t *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));

    switch (message) {
    case WM_NCCREATE: {
        CREATESTRUCTW *create_struct = reinterpret_cast<CREATESTRUCTW *>(l_param);
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(create_struct->lpCreateParams));
        return DefWindowProcW(hwnd, message, w_param, l_param);
    }
    case WM_CREATE:
        state = reinterpret_cast<renderer_window_state_t *>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
        request_snapshot(state, hwnd);
        if (state != nullptr && state->callbacks.on_window_ready != nullptr) {
            state->callbacks.on_window_ready(state->callbacks.context, reinterpret_cast<void *>(hwnd));
        }
        if (state != nullptr && state->auto_close_ms > 0) {
            SetTimer(hwnd, TIMER_AUTOCLOSE, static_cast<UINT>(state->auto_close_ms), nullptr);
        }
        if (state != nullptr && state->scripted_action_requested) {
            SetTimer(hwnd, TIMER_SCRIPTED_CLICK, static_cast<UINT>(std::max<int32_t>(1, state->scripted_action_delay_ms)), nullptr);
        }
        return 0;
    case WM_RENDERER_REDRAW:
        request_snapshot(state, hwnd);
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
    case WM_SIZE:
        if (state != nullptr && state->render_target != nullptr) {
            const UINT width = static_cast<UINT>(LOWORD(l_param));
            const UINT height = static_cast<UINT>(HIWORD(l_param));
            state->render_target->Resize(D2D1::SizeU(std::max<UINT>(1, width), std::max<UINT>(1, height)));
        }
        request_snapshot(state, hwnd);
        InvalidateRect(hwnd, nullptr, FALSE);
        return 0;
    case WM_LBUTTONDOWN:
        if (state != nullptr) {
            const renderer_win32_point_t point = {
                static_cast<double>(GET_X_LPARAM(l_param)),
                static_cast<double>(GET_Y_LPARAM(l_param)),
            };
            state->pointer_down = true;
            state->drag_started = false;
            state->long_press_dispatched = false;
            state->pointer_down_point = point;
            state->last_pointer_point = point;
            state->pointer_down_timestamp_ms = current_timestamp_ms();
            int32_t target_kind = -1;
            const std::string target_identifier = target_identifier_for_point(state, point, &target_kind);
            state->active_gesture_surface =
                target_kind == RENDERER_WIN32_FOCUS_GESTURE_SURFACE ? target_identifier : std::string();
            if (!state->active_gesture_surface.empty()) {
                SetTimer(hwnd, TIMER_LONG_PRESS, LONG_PRESS_DELAY_MS, nullptr);
            }
            SetCapture(hwnd);
            dispatch_pointer_event(state, hwnd, RENDERER_WIN32_POINTER_DOWN, point);
        }
        return 0;
    case WM_MOUSEMOVE:
        if (state != nullptr) {
            const renderer_win32_point_t point = {
                static_cast<double>(GET_X_LPARAM(l_param)),
                static_cast<double>(GET_Y_LPARAM(l_param)),
            };
            state->last_pointer_point = point;
            if (state->pointer_down) {
                dispatch_pointer_event(state, hwnd, RENDERER_WIN32_POINTER_MOVE, point);
                if (!state->active_gesture_surface.empty()) {
                    const double moved = distance_between(point, state->pointer_down_point);
                    if (!state->drag_started && moved >= DRAG_THRESHOLD) {
                        state->drag_started = true;
                        KillTimer(hwnd, TIMER_LONG_PRESS);
                        dispatch_drag_gesture(
                            state,
                            hwnd,
                            RENDERER_WIN32_GESTURE_DRAG_BEGAN,
                            state->active_gesture_surface,
                            state->pointer_down_point,
                            point
                        );
                    } else if (state->drag_started) {
                        dispatch_drag_gesture(
                            state,
                            hwnd,
                            RENDERER_WIN32_GESTURE_DRAG_CHANGED,
                            state->active_gesture_surface,
                            state->pointer_down_point,
                            point
                        );
                    } else if (moved >= DRAG_THRESHOLD) {
                        KillTimer(hwnd, TIMER_LONG_PRESS);
                    }
                }
            }
        }
        return 0;
    case WM_LBUTTONUP:
        if (state != nullptr) {
            const renderer_win32_point_t point = {
                static_cast<double>(GET_X_LPARAM(l_param)),
                static_cast<double>(GET_Y_LPARAM(l_param)),
            };
            const bool was_pointer_down = state->pointer_down;
            state->pointer_down = false;
            KillTimer(hwnd, TIMER_LONG_PRESS);
            dispatch_pointer_event(state, hwnd, RENDERER_WIN32_POINTER_UP, point);
            if (state->drag_started && !state->active_gesture_surface.empty()) {
                dispatch_drag_gesture(
                    state,
                    hwnd,
                    RENDERER_WIN32_GESTURE_DRAG_ENDED,
                    state->active_gesture_surface,
                    state->pointer_down_point,
                    point
                );
            } else if (!state->long_press_dispatched) {
                maybe_dispatch_swipe(state, hwnd, point);
            }

            if (!state->long_press_dispatched && was_pointer_down && state->snapshot != nullptr) {
                for (int index = static_cast<int>(state->snapshot->interaction_count) - 1; index >= 0; --index) {
                    const renderer_win32_interaction_t *interaction = &state->snapshot->interactions[index];
                    if (point_in_rect(point, interaction->rect)) {
                        handle_action(state, hwnd, interaction->action);
                        break;
                    }
                }
            }

            state->drag_started = false;
            state->active_gesture_surface.clear();
            ReleaseCapture();
        }
        return 0;
    case WM_CHAR:
        if (state != nullptr && state->snapshot != nullptr) {
            const renderer_win32_focus_region_t *focused = focused_region(state->snapshot, RENDERER_WIN32_FOCUS_TEXT_FIELD);
            if (focused != nullptr && w_param >= 32 && w_param != 127) {
                wchar_t wide_character = static_cast<wchar_t>(w_param);
                char utf8_buffer[8] = {0};
                const int converted = WideCharToMultiByte(
                    CP_UTF8,
                    0,
                    &wide_character,
                    1,
                    utf8_buffer,
                    static_cast<int>(sizeof(utf8_buffer)),
                    nullptr,
                    nullptr
                );
                if (converted > 0) {
                    const std::string inserted(utf8_buffer, utf8_buffer + converted);
                    const renderer_win32_text_input_t text_event = {
                        RENDERER_WIN32_TEXT_INSERT_TEXT,
                        focused->identifier,
                        string_to_utf8_view(inserted),
                    };
                    if (handle_text_input(state, hwnd, text_event)) {
                        return 0;
                    }
                }
            }
        }
        return DefWindowProcW(hwnd, message, w_param, l_param);
    case WM_MOUSEWHEEL:
        if (state != nullptr && state->snapshot != nullptr) {
            const POINT screen = { GET_X_LPARAM(l_param), GET_Y_LPARAM(l_param) };
            POINT client = screen;
            ScreenToClient(hwnd, &client);
            const renderer_win32_point_t point = { static_cast<double>(client.x), static_cast<double>(client.y) };
            int32_t target_kind = -1;
            const std::string target_identifier = target_identifier_for_point(state, point, &target_kind);
            if (target_kind == RENDERER_WIN32_FOCUS_GESTURE_SURFACE) {
                int32_t modifiers = current_modifier_mask();
                const UINT wheelKeys = GET_KEYSTATE_WPARAM(w_param);
                if ((wheelKeys & MK_SHIFT) != 0) {
                    modifiers |= 1;
                }
                if ((wheelKeys & MK_CONTROL) != 0) {
                    modifiers |= 2;
                }
                if ((modifiers & 2) != 0 || (modifiers & 4) != 0) {
                    const renderer_win32_gesture_event_t gesture_event = {
                        (modifiers & 2) != 0 ? RENDERER_WIN32_GESTURE_PINCH : RENDERER_WIN32_GESTURE_ROTATE,
                        string_to_utf8_view(target_identifier),
                        point.x,
                        point.y,
                        point.x,
                        point.y,
                        static_cast<double>(GET_WHEEL_DELTA_WPARAM(w_param)) / static_cast<double>(WHEEL_DELTA),
                        0,
                        static_cast<int64_t>(current_timestamp_ms()),
                    };
                    if (handle_gesture(state, hwnd, gesture_event)) {
                        return 0;
                    }
                }
            }
        }
        return DefWindowProcW(hwnd, message, w_param, l_param);
    case WM_KEYDOWN:
        if (state != nullptr) {
            if (handle_text_keydown(state, hwnd, w_param)) {
                return 0;
            }

            int32_t input_event = -1;
            switch (w_param) {
            case VK_TAB:
                input_event = (GetKeyState(VK_SHIFT) & 0x8000) != 0
                    ? RENDERER_WIN32_INPUT_FOCUS_PREVIOUS
                    : RENDERER_WIN32_INPUT_FOCUS_NEXT;
                break;
            case VK_UP:
                input_event = RENDERER_WIN32_INPUT_MOVE_UP;
                break;
            case VK_DOWN:
                input_event = RENDERER_WIN32_INPUT_MOVE_DOWN;
                break;
            case VK_LEFT:
                input_event = RENDERER_WIN32_INPUT_MOVE_LEFT;
                break;
            case VK_RIGHT:
                input_event = RENDERER_WIN32_INPUT_MOVE_RIGHT;
                break;
            case VK_RETURN:
            case VK_SPACE:
                input_event = RENDERER_WIN32_INPUT_ACTIVATE_FOCUSED;
                break;
            case VK_ESCAPE:
                input_event = RENDERER_WIN32_INPUT_BACK;
                break;
            default:
                break;
            }

            if (input_event >= 0 && handle_input(state, hwnd, input_event)) {
                return 0;
            }
        }
        return DefWindowProcW(hwnd, message, w_param, l_param);
    case WM_TIMER:
        if (w_param == TIMER_AUTOCLOSE) {
            KillTimer(hwnd, TIMER_AUTOCLOSE);
            DestroyWindow(hwnd);
        } else if (w_param == TIMER_SCRIPTED_CLICK) {
            KillTimer(hwnd, TIMER_SCRIPTED_CLICK);
            dispatch_scripted_click(state, hwnd);
        } else if (w_param == TIMER_LONG_PRESS) {
            KillTimer(hwnd, TIMER_LONG_PRESS);
            dispatch_long_press(state, hwnd);
        }
        return 0;
    case WM_ERASEBKGND:
        return 1;
    case WM_PAINT: {
        PAINTSTRUCT paint = {0};
        BeginPaint(hwnd, &paint);

        if (SUCCEEDED(ensure_render_target(state, hwnd)) && state != nullptr && state->snapshot != nullptr) {
            state->render_target->BeginDraw();
            state->render_target->Clear(make_color(state->snapshot->background_color));
            for (UINT32 index = 0; index < state->snapshot->command_count; ++index) {
                draw_command(state, &state->snapshot->commands[index]);
            }
            const HRESULT hr = state->render_target->EndDraw();
            if (hr == D2DERR_RECREATE_TARGET) {
                discard_device_resources(state);
            }
        }

        EndPaint(hwnd, &paint);
        return 0;
    }
    case WM_DESTROY:
        if (state != nullptr) {
            if (state->report != nullptr) {
                state->report->frame_count = state->frame_count;
                state->report->scripted_action_requested = state->scripted_action_requested ? 1 : 0;
                state->report->scripted_action_dispatched = state->scripted_action_dispatched ? 1 : 0;
            }
            release_snapshot(state);
            discard_device_resources(state);
            safe_release(reinterpret_cast<IUnknown **>(&state->dwrite_factory));
            safe_release(reinterpret_cast<IUnknown **>(&state->d2d_factory));
            safe_release(reinterpret_cast<IUnknown **>(&state->wic_factory));
            delete state;
        }
        PostQuitMessage(0);
        return 0;
    default:
        return DefWindowProcW(hwnd, message, w_param, l_param);
    }
}

} // namespace

extern "C" int32_t renderer_win32_run_window(
    renderer_win32_callbacks_t callbacks,
    renderer_win32_run_options_t options,
    renderer_win32_run_report_t *report
) {
    SetProcessDPIAware();
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

    HINSTANCE instance = GetModuleHandleW(nullptr);
    const wchar_t *class_name = L"LapMobileRendererWindow";

    WNDCLASSEXW window_class = {0};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = renderer_window_proc;
    window_class.hInstance = instance;
    window_class.lpszClassName = class_name;
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    RegisterClassExW(&window_class);

    renderer_window_state_t *state = new renderer_window_state_t();
    state->callbacks = callbacks;
    state->snapshot = nullptr;
    state->d2d_factory = nullptr;
    state->dwrite_factory = nullptr;
    state->wic_factory = nullptr;
    state->render_target = nullptr;
    state->brush = nullptr;
    state->report = report;
    state->auto_close_ms = options.auto_close_ms;
    state->scripted_action_delay_ms = options.scripted_action_delay_ms;
    state->frame_count = 0;
    state->scripted_action_requested = options.scripted_action.length > 0;
    state->scripted_action_dispatched = false;
    state->scripted_action = utf8_to_string(options.scripted_action);
    state->pointer_down = false;
    state->drag_started = false;
    state->long_press_dispatched = false;
    state->pointer_down_point = renderer_win32_point_t { 0.0, 0.0 };
    state->last_pointer_point = renderer_win32_point_t { 0.0, 0.0 };
    state->pointer_down_timestamp_ms = 0;

    if (report != nullptr) {
        report->frame_count = 0;
        report->scripted_action_requested = state->scripted_action_requested ? 1 : 0;
        report->scripted_action_dispatched = 0;
    }

    std::wstring title = utf8_to_utf16(options.window_title);
    if (title.empty()) {
        title = L"lap_mobile ui demo";
    }

    HWND hwnd = CreateWindowExW(
        0,
        class_name,
        title.c_str(),
        WS_OVERLAPPEDWINDOW,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        std::max<int32_t>(320, options.width),
        std::max<int32_t>(480, options.height),
        nullptr,
        nullptr,
        instance,
        state
    );

    if (hwnd == nullptr) {
        delete state;
        CoUninitialize();
        return 1;
    }

    ShowWindow(hwnd, SW_SHOWDEFAULT);
    UpdateWindow(hwnd);

    MSG message = {0};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }

    CoUninitialize();
    return static_cast<int32_t>(message.wParam);
}

extern "C" void renderer_win32_request_redraw(renderer_win32_redraw_handle_t handle) {
    if (handle == nullptr) {
        return;
    }
    PostMessageW(reinterpret_cast<HWND>(handle), WM_RENDERER_REDRAW, 0, 0);
}

extern "C" void renderer_win32_send_virtual_key(
    renderer_win32_redraw_handle_t handle,
    uint32_t virtual_key,
    int32_t shift_down
) {
    if (handle == nullptr) {
        return;
    }

    HWND hwnd = reinterpret_cast<HWND>(handle);
    if (shift_down != 0) {
        PostMessageW(hwnd, WM_KEYDOWN, VK_SHIFT, 0);
    }
    PostMessageW(hwnd, WM_KEYDOWN, static_cast<WPARAM>(virtual_key), 0);
    PostMessageW(hwnd, WM_KEYUP, static_cast<WPARAM>(virtual_key), 0);
    if (shift_down != 0) {
        PostMessageW(hwnd, WM_KEYUP, VK_SHIFT, 0);
    }
}

extern "C" void renderer_win32_send_character(
    renderer_win32_redraw_handle_t handle,
    uint32_t scalar_value
) {
    if (handle == nullptr) {
        return;
    }
    PostMessageW(reinterpret_cast<HWND>(handle), WM_CHAR, static_cast<WPARAM>(scalar_value), 0);
}

extern "C" void renderer_win32_send_pointer_event(
    renderer_win32_redraw_handle_t handle,
    int32_t phase,
    double x,
    double y,
    int32_t modifiers
) {
    if (handle == nullptr) {
        return;
    }

    HWND hwnd = reinterpret_cast<HWND>(handle);
    WPARAM flags = 0;
    if ((modifiers & 1) != 0) {
        flags |= MK_SHIFT;
    }
    if ((modifiers & 2) != 0) {
        flags |= MK_CONTROL;
    }

    switch (phase) {
    case RENDERER_WIN32_POINTER_DOWN:
        PostMessageW(hwnd, WM_LBUTTONDOWN, flags | MK_LBUTTON, MAKELPARAM(static_cast<LONG>(x), static_cast<LONG>(y)));
        break;
    case RENDERER_WIN32_POINTER_MOVE:
        PostMessageW(hwnd, WM_MOUSEMOVE, flags | MK_LBUTTON, MAKELPARAM(static_cast<LONG>(x), static_cast<LONG>(y)));
        break;
    case RENDERER_WIN32_POINTER_UP:
        PostMessageW(hwnd, WM_LBUTTONUP, flags, MAKELPARAM(static_cast<LONG>(x), static_cast<LONG>(y)));
        break;
    case RENDERER_WIN32_POINTER_CANCEL:
        PostMessageW(hwnd, WM_CANCELMODE, 0, 0);
        break;
    default:
        break;
    }
}

extern "C" void renderer_win32_send_wheel_event(
    renderer_win32_redraw_handle_t handle,
    int32_t wheel_delta,
    double x,
    double y,
    int32_t modifiers
) {
    if (handle == nullptr) {
        return;
    }

    HWND hwnd = reinterpret_cast<HWND>(handle);
    POINT point = { static_cast<LONG>(x), static_cast<LONG>(y) };
    ClientToScreen(hwnd, &point);

    WPARAM flags = MAKEWPARAM(0, static_cast<WORD>(wheel_delta));
    if ((modifiers & 1) != 0) {
        flags |= MK_SHIFT;
    }
    if ((modifiers & 2) != 0) {
        flags |= MK_CONTROL;
    }

    if ((modifiers & 4) != 0) {
        keybd_event(VK_MENU, 0, 0, 0);
    }
    SendMessageW(hwnd, WM_MOUSEWHEEL, flags, MAKELPARAM(point.x, point.y));
    if ((modifiers & 4) != 0) {
        keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, 0);
    }
}

#else

extern "C" int32_t renderer_win32_run_window(
    renderer_win32_callbacks_t callbacks,
    renderer_win32_run_options_t options,
    renderer_win32_run_report_t *report
) {
    (void)callbacks;
    (void)options;
    if (report != nullptr) {
        report->frame_count = 0;
        report->scripted_action_requested = 0;
        report->scripted_action_dispatched = 0;
    }
    return -1;
}

extern "C" void renderer_win32_request_redraw(renderer_win32_redraw_handle_t handle) {
    (void)handle;
}

extern "C" void renderer_win32_send_virtual_key(
    renderer_win32_redraw_handle_t handle,
    uint32_t virtual_key,
    int32_t shift_down
) {
    (void)handle;
    (void)virtual_key;
    (void)shift_down;
}

extern "C" void renderer_win32_send_character(renderer_win32_redraw_handle_t handle, uint32_t scalar_value) {
    (void)handle;
    (void)scalar_value;
}

extern "C" void renderer_win32_send_pointer_event(
    renderer_win32_redraw_handle_t handle,
    int32_t phase,
    double x,
    double y,
    int32_t modifiers
) {
    (void)handle;
    (void)phase;
    (void)x;
    (void)y;
    (void)modifiers;
}

extern "C" void renderer_win32_send_wheel_event(
    renderer_win32_redraw_handle_t handle,
    int32_t wheel_delta,
    double x,
    double y,
    int32_t modifiers
) {
    (void)handle;
    (void)wheel_delta;
    (void)x;
    (void)y;
    (void)modifiers;
}

#endif
