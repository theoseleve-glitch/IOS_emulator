#ifndef RENDERER_WIN32_SHIM_H
#define RENDERER_WIN32_SHIM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct renderer_win32_string {
    const char *data;
    uint32_t length;
} renderer_win32_string_t;

typedef struct renderer_win32_point {
    double x;
    double y;
} renderer_win32_point_t;

typedef struct renderer_win32_rect {
    double x;
    double y;
    double width;
    double height;
} renderer_win32_rect_t;

typedef struct renderer_win32_color {
    double red;
    double green;
    double blue;
    double alpha;
} renderer_win32_color_t;

typedef struct renderer_win32_text_style {
    renderer_win32_string_t font_family;
    double font_size;
    int32_t font_weight;
    int32_t horizontal_alignment;
    renderer_win32_color_t color;
} renderer_win32_text_style_t;

enum {
    RENDERER_WIN32_COMMAND_FILL = 0,
    RENDERER_WIN32_COMMAND_STROKE = 1,
    RENDERER_WIN32_COMMAND_LINE = 2,
    RENDERER_WIN32_COMMAND_TEXT = 3,
    RENDERER_WIN32_COMMAND_IMAGE = 4,
};

typedef struct renderer_win32_command {
    int32_t kind;
    renderer_win32_rect_t rect;
    renderer_win32_point_t from_point;
    renderer_win32_point_t to_point;
    renderer_win32_color_t color;
    double line_width;
    double corner_radius;
    renderer_win32_string_t text;
    renderer_win32_string_t image_name;
    renderer_win32_string_t image_path;
    renderer_win32_text_style_t text_style;
} renderer_win32_command_t;

typedef struct renderer_win32_interaction {
    renderer_win32_rect_t rect;
    renderer_win32_string_t action;
} renderer_win32_interaction_t;

enum {
    RENDERER_WIN32_FOCUS_ACTION = 0,
    RENDERER_WIN32_FOCUS_TEXT_FIELD = 1,
    RENDERER_WIN32_FOCUS_GESTURE_SURFACE = 2,
};

typedef struct renderer_win32_focus_region {
    renderer_win32_rect_t rect;
    int32_t kind;
    renderer_win32_string_t identifier;
    int32_t is_focused;
} renderer_win32_focus_region_t;

typedef struct renderer_win32_snapshot {
    void *user_data;
    renderer_win32_string_t title;
    renderer_win32_color_t background_color;
    int32_t viewport_width;
    int32_t viewport_height;
    const renderer_win32_command_t *commands;
    uint32_t command_count;
    const renderer_win32_interaction_t *interactions;
    uint32_t interaction_count;
    const renderer_win32_focus_region_t *focus_regions;
    uint32_t focus_region_count;
} renderer_win32_snapshot_t;

typedef renderer_win32_snapshot_t *(*renderer_win32_make_frame_fn)(void *context, int32_t width, int32_t height);
typedef void (*renderer_win32_release_frame_fn)(void *context, renderer_win32_snapshot_t *snapshot);
typedef void (*renderer_win32_action_fn)(void *context, renderer_win32_string_t action);
typedef int32_t (*renderer_win32_input_fn)(void *context, int32_t input_event);
typedef void *renderer_win32_redraw_handle_t;
typedef void (*renderer_win32_window_ready_fn)(void *context, renderer_win32_redraw_handle_t handle);

enum {
    RENDERER_WIN32_TEXT_INSERT_TEXT = 0,
    RENDERER_WIN32_TEXT_DELETE_BACKWARD = 1,
    RENDERER_WIN32_TEXT_DELETE_FORWARD = 2,
    RENDERER_WIN32_TEXT_MOVE_CARET_LEFT = 3,
    RENDERER_WIN32_TEXT_MOVE_CARET_RIGHT = 4,
    RENDERER_WIN32_TEXT_MOVE_CARET_TO_START = 5,
    RENDERER_WIN32_TEXT_MOVE_CARET_TO_END = 6,
    RENDERER_WIN32_TEXT_SUBMIT = 7,
};

typedef struct renderer_win32_text_input {
    int32_t kind;
    renderer_win32_string_t field_id;
    renderer_win32_string_t text;
} renderer_win32_text_input_t;

enum {
    RENDERER_WIN32_POINTER_DOWN = 0,
    RENDERER_WIN32_POINTER_MOVE = 1,
    RENDERER_WIN32_POINTER_UP = 2,
    RENDERER_WIN32_POINTER_CANCEL = 3,
};

typedef struct renderer_win32_pointer_event {
    int32_t phase;
    double x;
    double y;
    int32_t modifiers;
    int32_t target_kind;
    renderer_win32_string_t target_identifier;
    int64_t timestamp_ms;
} renderer_win32_pointer_event_t;

enum {
    RENDERER_WIN32_GESTURE_DRAG_BEGAN = 0,
    RENDERER_WIN32_GESTURE_DRAG_CHANGED = 1,
    RENDERER_WIN32_GESTURE_DRAG_ENDED = 2,
    RENDERER_WIN32_GESTURE_SWIPE = 3,
    RENDERER_WIN32_GESTURE_LONG_PRESS = 4,
    RENDERER_WIN32_GESTURE_PINCH = 5,
    RENDERER_WIN32_GESTURE_ROTATE = 6,
};

typedef struct renderer_win32_gesture_event {
    int32_t kind;
    renderer_win32_string_t surface_id;
    double start_x;
    double start_y;
    double current_x;
    double current_y;
    double delta;
    int32_t direction;
    int64_t timestamp_ms;
} renderer_win32_gesture_event_t;

typedef int32_t (*renderer_win32_text_input_fn)(void *context, renderer_win32_text_input_t input_event);
typedef int32_t (*renderer_win32_pointer_fn)(void *context, renderer_win32_pointer_event_t pointer_event);
typedef int32_t (*renderer_win32_gesture_fn)(void *context, renderer_win32_gesture_event_t gesture_event);

enum {
    RENDERER_WIN32_INPUT_FOCUS_NEXT = 0,
    RENDERER_WIN32_INPUT_FOCUS_PREVIOUS = 1,
    RENDERER_WIN32_INPUT_MOVE_UP = 2,
    RENDERER_WIN32_INPUT_MOVE_DOWN = 3,
    RENDERER_WIN32_INPUT_MOVE_LEFT = 4,
    RENDERER_WIN32_INPUT_MOVE_RIGHT = 5,
    RENDERER_WIN32_INPUT_ACTIVATE_FOCUSED = 6,
    RENDERER_WIN32_INPUT_BACK = 7,
};

typedef struct renderer_win32_callbacks {
    void *context;
    renderer_win32_make_frame_fn make_frame;
    renderer_win32_release_frame_fn release_frame;
    renderer_win32_action_fn on_action;
    renderer_win32_input_fn on_input;
    renderer_win32_text_input_fn on_text_input;
    renderer_win32_pointer_fn on_pointer;
    renderer_win32_gesture_fn on_gesture;
    renderer_win32_window_ready_fn on_window_ready;
} renderer_win32_callbacks_t;

typedef struct renderer_win32_run_options {
    renderer_win32_string_t window_title;
    int32_t width;
    int32_t height;
    int32_t auto_close_ms;
    renderer_win32_string_t scripted_action;
    int32_t scripted_action_delay_ms;
} renderer_win32_run_options_t;

typedef struct renderer_win32_run_report {
    int32_t frame_count;
    int32_t scripted_action_requested;
    int32_t scripted_action_dispatched;
} renderer_win32_run_report_t;

int32_t renderer_win32_run_window(
    renderer_win32_callbacks_t callbacks,
    renderer_win32_run_options_t options,
    renderer_win32_run_report_t *report
);

void renderer_win32_request_redraw(renderer_win32_redraw_handle_t handle);
void renderer_win32_send_virtual_key(renderer_win32_redraw_handle_t handle, uint32_t virtual_key, int32_t shift_down);
void renderer_win32_send_character(renderer_win32_redraw_handle_t handle, uint32_t scalar_value);
void renderer_win32_send_pointer_event(
    renderer_win32_redraw_handle_t handle,
    int32_t phase,
    double x,
    double y,
    int32_t modifiers
);
void renderer_win32_send_wheel_event(
    renderer_win32_redraw_handle_t handle,
    int32_t wheel_delta,
    double x,
    double y,
    int32_t modifiers
);

#ifdef __cplusplus
}
#endif

#endif
