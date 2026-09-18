//#include <pybind11/pybind11.h>
#include "engine.h"
#include "resource_manager.h"
#include "lua_callbacks.h"
#include "lua_http.h"
#include "lua_http_server.h"
#include "lua_process.h"
#include "cgltf_jobs.h"
#include "lua_jobs.h"
#include "lua_keyring.h"
#include "log.h"
#include "input_coordinates.h"
#include "input_mouse_state.h"
#include "lua_video.h"
#include "video_player.h"
#include "cef_runtime.h"

#include <cstdlib>
#include <optional>
#include <cinttypes>
#include <stdexcept>
#include <utility>
#include <vector>

//namespace py = pybind11;
namespace {

sol::table make_int_array(sol::state& lua, const std::vector<int>& values)
{
    sol::table out = lua.create_table();
    for (size_t i = 0; i < values.size(); ++i) {
        out[static_cast<int>(i + 1)] = values[i];
    }
    return out;
}

Uint64 ns_to_ms(Uint64 timestamp_ns)
{
    return timestamp_ns / 1000000ULL;
}

const char* startup_mode_to_string(WindowStartupMode mode)
{
    if (mode == WindowStartupMode::Windowed) {
        return "windowed";
    }
    if (mode == WindowStartupMode::Maximized) {
        return "maximized";
    }
    return "fullscreen";
}

const char* power_state_to_string(SDL_PowerState state)
{
    switch (state) {
        case SDL_POWERSTATE_ERROR:
            return "error";
        case SDL_POWERSTATE_UNKNOWN:
            return "unknown";
        case SDL_POWERSTATE_ON_BATTERY:
            return "on_battery";
        case SDL_POWERSTATE_NO_BATTERY:
            return "no_battery";
        case SDL_POWERSTATE_CHARGING:
            return "charging";
        case SDL_POWERSTATE_CHARGED:
            return "charged";
        default:
            return "unknown";
    }
}

bool is_on_battery(SDL_PowerState state)
{
    return state == SDL_POWERSTATE_ON_BATTERY;
}

bool compiled_with_wayland_backend()
{
#ifdef SDL_VIDEO_DRIVER_WAYLAND
    return true;
#else
    return false;
#endif
}

bool compiled_with_x11_xinput2()
{
#ifdef SDL_VIDEO_DRIVER_X11_XINPUT2
    return true;
#else
    return false;
#endif
}

void log_input_backend_summary()
{
    const char* current_driver = SDL_GetCurrentVideoDriver();
    const char* session_type = std::getenv("XDG_SESSION_TYPE");
    int touch_count = 0;
    SDL_TouchID* touch_ids = SDL_GetTouchDevices(&touch_count);
    SDL_free(touch_ids);

    LOG_NAMED("input", Info)
        << log_kv("session_type", session_type ? session_type : "")
        << log_kv("video_driver", current_driver ? current_driver : "")
        << log_kv("compiled_wayland", compiled_with_wayland_backend())
        << log_kv("compiled_x11_xinput2", compiled_with_x11_xinput2())
        << log_kv("touch_devices", touch_count)
        << "SDL input backend summary";

    if (session_type
        && std::string(session_type) == "wayland"
        && current_driver
        && std::string(current_driver) == "x11")
    {
        LOG_NAMED("input", Warning)
            << log_kv("session_type", session_type)
            << log_kv("video_driver", current_driver)
            << log_kv("compiled_wayland", compiled_with_wayland_backend())
            << log_kv("compiled_x11_xinput2", compiled_with_x11_xinput2())
            << "Wayland session is running through SDL X11/Xwayland backend; native touch and pen events may be unavailable";
    }
}

void log_touch_event(const SDL_Event& event, const char* stage)
{
    const char* event_name = "touch";
    bool canceled = false;
    switch (event.type) {
        case SDL_EVENT_FINGER_DOWN:
            event_name = "finger-down";
            break;
        case SDL_EVENT_FINGER_MOTION:
            event_name = "finger-motion";
            break;
        case SDL_EVENT_FINGER_UP:
            event_name = "finger-up";
            break;
        case SDL_EVENT_FINGER_CANCELED:
            event_name = "finger-canceled";
            canceled = true;
            break;
        default:
            return;
    }

    LOG_NAMED("input", Debug)
        << log_kv("stage", stage)
        << log_kv("event", event_name)
        << log_kv("touch_id", static_cast<long long>(event.tfinger.touchID))
        << log_kv("finger_id", static_cast<long long>(event.tfinger.fingerID))
        << log_kv("window_id", static_cast<int>(event.tfinger.windowID))
        << log_kv("x", event.tfinger.x)
        << log_kv("y", event.tfinger.y)
        << log_kv("dx", event.tfinger.dx)
        << log_kv("dy", event.tfinger.dy)
        << log_kv("pressure", event.tfinger.pressure)
        << log_kv("canceled", canceled)
        << log_kv("timestamp_ms", ns_to_ms(event.common.timestamp))
        << "Native SDL touch event";
}

std::pair<float, float> touch_window_coordinates(sol::table engine_table,
                                                 WindowSdl* window,
                                                 float normalized_x,
                                                 float normalized_y)
{
    int window_width = 0;
    int window_height = 0;
    if (window) {
        window->getWindowSize(window_width, window_height);
    }
    if (window_width <= 0) {
        sol::optional<int> engine_width = engine_table["width"];
        window_width = engine_width.value_or(0);
    }
    if (window_height <= 0) {
        sol::optional<int> engine_height = engine_table["height"];
        window_height = engine_height.value_or(0);
    }
    if (window_width <= 0) {
        sol::optional<int> engine_width = engine_table["pixel-width"];
        window_width = engine_width.value_or(0);
    }
    if (window_height <= 0) {
        sol::optional<int> engine_height = engine_table["pixel-height"];
        window_height = engine_height.value_or(0);
    }
    return normalized_to_window_coordinates(normalized_x, normalized_y, window_width, window_height);
}

void set_pen_axes(sol::table& payload, const InputState::PenState* pen)
{
    payload["pressure"] = pen ? pen->axis(SDL_PEN_AXIS_PRESSURE) : 0.0F;
    payload["x-tilt"] = pen ? pen->axis(SDL_PEN_AXIS_XTILT) : 0.0F;
    payload["y-tilt"] = pen ? pen->axis(SDL_PEN_AXIS_YTILT) : 0.0F;
    payload["distance"] = pen ? pen->axis(SDL_PEN_AXIS_DISTANCE) : 0.0F;
    payload["rotation"] = pen ? pen->axis(SDL_PEN_AXIS_ROTATION) : 0.0F;
    payload["slider"] = pen ? pen->axis(SDL_PEN_AXIS_SLIDER) : 0.0F;
    payload["tangential-pressure"] = pen ? pen->axis(SDL_PEN_AXIS_TANGENTIAL_PRESSURE) : 0.0F;
}

sol::table make_pen_payload(sol::state& lua,
                            const InputState::PenState* pen,
                            SDL_PenID pen_id,
                            SDL_PenInputFlags pen_state,
                            float x,
                            float y,
                            Uint64 timestamp)
{
    sol::table payload = lua.create_table();
    payload["pen-id"] = static_cast<lua_Integer>(pen_id);
    payload["x"] = x;
    payload["y"] = y;
    payload["xrel"] = pen ? pen->xrel : 0.0F;
    payload["yrel"] = pen ? pen->yrel : 0.0F;
    payload["pen-state"] = pen_state;
    payload["down"] = pen ? pen->currentDown : ((pen_state & SDL_PEN_INPUT_DOWN) != 0);
    payload["in-range"] = pen ? pen->currentInRange : true;
    payload["eraser"] = pen ? pen->eraser : ((pen_state & SDL_PEN_INPUT_ERASER_TIP) != 0);
    payload["mod"] = static_cast<int>(SDL_GetModState());
    payload["timestamp"] = timestamp;
    set_pen_axes(payload, pen);
    return payload;
}

} // namespace

Engine::Engine() {
}

bool Engine::start(sol::state& lua, sol::table engine_table, const EngineConfig& config) {
    headless_mode_ = config.headless;
    log_set_frame_id_provider(&frame_id);
    SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0");
    SDL_SetHint(SDL_HINT_MOUSE_TOUCH_EVENTS, "0");
    SDL_SetHint(SDL_HINT_PEN_MOUSE_EVENTS, "0");
    SDL_SetHint(SDL_HINT_PEN_TOUCH_EVENTS, "0");
    auto initialize_keyboard_state = [this]() {
        inputState.keyboardState.currentValue = SDL_GetKeyboardState(nullptr);
        if (inputState.keyboardState.currentValue == nullptr) {
            throw std::runtime_error("SDL keyboard state is unavailable after engine startup");
        }
        std::memset(inputState.keyboardState.previousValue, 0, SDL_SCANCODE_COUNT);
    };
    if (!config.headless) {
        window = WindowSdl::create(config.title);
        int target_width = config.width > 0 ? config.width : screenWidth;
        int target_height = config.height > 0 ? config.height : screenHeight;
        if (!window->init(target_width, target_height, config.window_mode)) {
            return false;
        }
        initialize_keyboard_state();
        window->setTextInputEnabled(false);
        window->logGlParams();

        initSystemCursors();
        SDL_SetGamepadEventsEnabled(true);
        log_input_backend_summary();
        screensaver_inhibited_ = !SDL_ScreenSaverEnabled();
        {
            float mouseX = 0.0F;
            float mouseY = 0.0F;
            SDL_MouseButtonFlags mouseMask = SDL_GetMouseState(&mouseX, &mouseY);
            inputState.mouseState.update_from_mask(mouseMask);
            inputState.mouseState.set_motion(mouseX, mouseY, 0.0F, 0.0F);
        }

        int gamepad_count = 0;
        SDL_JoystickID* gamepad_ids = SDL_GetGamepads(&gamepad_count);
        for (int i = 0; i < gamepad_count; ++i) {
            openGamepad(gamepad_ids[i], SDL_GetTicks());
        }
        SDL_free(gamepad_ids);
    } else {
        const SDL_InitFlags init_flags = SDL_INIT_EVENTS;
        if (!SDL_Init(init_flags)) {
            LOG(Error) << "SDL headless initialisation failed";
            LOG(Error) << SDL_GetError();
            return false;
        }
        sdl_headless_initialized_ = true;
        initialize_keyboard_state();
    }

    jobs = std::make_unique<JobSystem>();
    register_default_job_handlers(*jobs);
    register_texture_job_handlers(*jobs);
    register_audio_job_handlers(*jobs);
    register_cgltf_job_handlers(*jobs);
    ResourceManager::setJobSystem(jobs.get());
    ResourceManager::setAudio(&audio);
    video_manager.set_audio(&audio);
    lua_video_set_manager(lua, &video_manager);

    lua_state = &lua;
    lua_engine = engine_table;
    lua_engine["frame-id"] = frame_id.load(std::memory_order_relaxed);
    lua_engine["window-mode"] = startup_mode_to_string(config.window_mode);
    if (!config.headless) {
        int actual_width = 0;
        int actual_height = 0;
        int actual_pixel_width = 0;
        int actual_pixel_height = 0;
        if (window && window->getWindowSize(actual_width, actual_height)) {
            lua_engine["width"] = actual_width;
            lua_engine["height"] = actual_height;
        } else {
            int target_width = config.width > 0 ? config.width : screenWidth;
            int target_height = config.height > 0 ? config.height : screenHeight;
            lua_engine["width"] = target_width;
            lua_engine["height"] = target_height;
        }
        if (window && window->getWindowSizeInPixels(actual_pixel_width, actual_pixel_height)) {
            lua_engine["pixel-width"] = actual_pixel_width;
            lua_engine["pixel-height"] = actual_pixel_height;
        } else {
            lua_engine["pixel-width"] = lua_engine["width"];
            lua_engine["pixel-height"] = lua_engine["height"];
        }
    }
    lua_engine.set_function("quit", [this]() {
        this->quit();
    });
    lua_engine.set_function("set-system-cursor", [this](const std::string& name) {
        this->setSystemCursor(name);
    });
    lua_engine.set_function("set-text-input-enabled", [this](bool enabled) {
        this->setTextInputEnabled(enabled);
    });
    lua_engine.set_function("set-screen-locked", [this](bool locked) {
        sol::table payload = lua_state->create_table();
        payload["locked"] = locked;
        payload["timestamp"] = SDL_GetTicks();
        emit_engine_event("screen-locked-changed", payload);
    });
    lua_engine.set_function("is-on-battery", []() {
        int seconds_left = -1;
        int percent = -1;
        SDL_PowerState state = SDL_GetPowerInfo(&seconds_left, &percent);
        (void)seconds_left;
        (void)percent;
        return is_on_battery(state);
    });
    lua_engine.set_function("has-active-video-playback", [this]() {
        return video_manager.has_active_playback();
    });
    lua_engine.set_function("set-target-fps", [this](int fps) {
        timer.setTargetFps(fps);
        lua_engine["target-fps"] = timer.getTargetFps();
    });
    lua_engine.set_function("get-target-fps", [this]() {
        return timer.getTargetFps();
    });
    lua_engine.set_function("set-physics-paused", [this](bool paused) {
        physics_paused_ = paused;
        lua_engine["physics-paused"] = physics_paused_;
    });
    lua_engine.set_function("get-physics-paused", [this]() {
        return physics_paused_;
    });
    lua_engine.set_function("set-input-paused", [this](bool paused) {
        input_paused_ = paused;
        lua_engine["input-paused"] = input_paused_;
    });
    lua_engine.set_function("get-input-paused", [this]() {
        return input_paused_;
    });
    lua_engine.set_function("set-ui-paused", [this](bool paused) {
        ui_paused_ = paused;
        lua_engine["ui-paused"] = ui_paused_;
    });
    lua_engine.set_function("get-ui-paused", [this]() {
        return ui_paused_;
    });
    lua_engine.set_function("set-screensaver-inhibited", [this](bool inhibited) {
        if (!setScreensaverInhibited(inhibited)) {
            throw std::runtime_error(inhibited ? "failed to disable SDL screensaver"
                                               : "failed to enable SDL screensaver");
        }
        return true;
    });
    lua_engine.set_function("screensaver-enabled", []() {
        return SDL_ScreenSaverEnabled();
    });
    request_frame_event_type = SDL_RegisterEvents(1);
    if (request_frame_event_type == static_cast<Uint32>(-1)) {
        LOG(Warning) << "Failed to allocate request-frame event type: " << SDL_GetError();
        SDL_ClearError();
    }
    lua_engine.set_function("request-frame", [this]() {
        if (request_frame_event_type == static_cast<Uint32>(-1)) {
            return false;
        }
        SDL_Event event {};
        event.type = request_frame_event_type;
        return SDL_PushEvent(&event) == 1;
    });
    lua_engine["target-fps"] = timer.getTargetFps();
    lua_engine["physics-paused"] = physics_paused_;
    lua_engine["input-paused"] = input_paused_;
    lua_engine["ui-paused"] = ui_paused_;
    lua_engine["screensaver-inhibited"] = screensaver_inhibited_;
    lua_bind_callbacks(*lua_state, lua_engine);
    lua_engine["physics"] = &physics;
    lua_engine["audio"] = &audio;
    lua_engine["input"] = &inputState;
    inputDialType = std::make_unique<InputDialType>(inputState);
    lua_engine.set_function("dial-type-activate", [this](int instance_id) {
        if (inputDialType) {
            inputDialType->activate_gamepad(static_cast<SDL_JoystickID>(instance_id));
        }
    });
    lua_engine.set_function("dial-type-deactivate", [this](int instance_id) {
        if (inputDialType) {
            inputDialType->deactivate_gamepad(static_cast<SDL_JoystickID>(instance_id));
        }
    });
    lua_engine.set_function("dial-type-on-input", [this](int instance_id, sol::function callback) {
        if (!inputDialType) {
            return static_cast<uint64_t>(0);
        }
        auto cb = std::make_shared<sol::protected_function>(callback);
        return inputDialType->register_callback(
            static_cast<SDL_JoystickID>(instance_id),
            [this, cb](SDL_JoystickID gamepad_id, const DialTypePendingInput& input) {
                if (!lua_state || !cb || !cb->valid()) {
                    return;
                }
                sol::table payload = lua_state->create_table();
                payload["instance-id"] = static_cast<int>(gamepad_id);
                sol::table in = lua_state->create_table();
                in[1] = make_int_array(*lua_state, input.left);
                in[2] = make_int_array(*lua_state, input.right);
                payload["input"] = in;
                sol::protected_function_result result = (*cb)(payload);
                if (!result.valid()) {
                    sol::error err = result;
                    std::cerr << "[dial-type] callback failed: " << err.what() << "\n";
                }
            });
    });
    lua_engine.set_function("dial-type-off-input", [this](uint64_t callback_id) {
        if (!inputDialType) {
            return false;
        }
        return inputDialType->unregister_callback(callback_id);
    });
    lua_bind_jobs(*lua_state, lua_engine, *jobs);
    lua_bind_keyring(*lua_state, keyring);
    {
        sol::table mouse_buttons = lua_state->create_table();
        mouse_buttons["left"] = SDL_BUTTON_LEFT;
        mouse_buttons["middle"] = SDL_BUTTON_MIDDLE;
        mouse_buttons["right"] = SDL_BUTTON_RIGHT;
        mouse_buttons["x1"] = SDL_BUTTON_X1;
        mouse_buttons["x2"] = SDL_BUTTON_X2;
        lua_engine["mouse-buttons"] = mouse_buttons;
    }
    {
        sol::table browser_table = lua_state->create_table();
        browser_table.set_function("create-surface", [this](sol::table options) {
            browser::SurfaceConfig config;
            sol::optional<std::string> id = options["id"];
            sol::optional<std::string> url = options["url"];
            if (!id || id->empty()) {
                throw sol::error("engine.browser.create-surface requires id");
            }
            if (!url || url->empty()) {
                throw sol::error("engine.browser.create-surface requires url");
            }
            config.id = *id;
            config.url = *url;
            if (sol::optional<std::string> texture_name = options["texture-name"]) {
                config.texture_name = *texture_name;
            }
            if (sol::optional<int> width = options["width"]) {
                if (*width <= 0) {
                    throw sol::error("engine.browser.create-surface width must be > 0");
                }
                config.width = static_cast<std::uint32_t>(*width);
            }
            if (sol::optional<int> height = options["height"]) {
                if (*height <= 0) {
                    throw sol::error("engine.browser.create-surface height must be > 0");
                }
                config.height = static_cast<std::uint32_t>(*height);
            }
            if (sol::optional<int> max_fps = options["max-fps"]) {
                if (*max_fps <= 0) {
                    throw sol::error("engine.browser.create-surface max-fps must be > 0");
                }
                config.max_fps = static_cast<std::uint32_t>(*max_fps);
            }
            return browser_system.create_surface(config);
        });
        browser_table.set_function("destroy-surface", [this](const std::string& id) {
            return browser_system.destroy_surface(id);
        });
        browser_table.set_function("set-url", [this](const std::string& id, const std::string& url) {
            return browser_system.set_surface_url(id, url);
        });
        browser_table.set_function("set-visible", [this](const std::string& id, bool visible) {
            browser_system.set_surface_visible(id, visible);
        });
        browser_table.set_function("set-focus", [this](const std::string& id, bool focused) {
            return browser_system.set_surface_focus(id, focused);
        });
        browser_table.set_function("send-mouse-move", [this](const std::string& id, int x, int y, sol::object leave_opt) {
            bool leave = false;
            if (leave_opt.is<bool>()) {
                leave = leave_opt.as<bool>();
            }
            return browser_system.send_mouse_move(id, x, y, leave);
        });
        browser_table.set_function("send-mouse-click",
            [this](const std::string& id, int x, int y, int button, bool mouse_up, sol::optional<int> click_count) {
                return browser_system.send_mouse_click(id, x, y, button, mouse_up, click_count.value_or(1));
            });
        browser_table.set_function("send-mouse-wheel", [this](const std::string& id, int x, int y, int dx, int dy) {
            return browser_system.send_mouse_wheel(id, x, y, dx, dy);
        });
        browser_table.set_function("texture-name", [this](const std::string& id) -> sol::object {
            std::optional<std::string> texture_name = browser_system.get_surface_texture_name(id);
            if (!texture_name) {
                return sol::make_object(*lua_state, sol::nil);
            }
            return sol::make_object(*lua_state, *texture_name);
        });
        browser_table.set_function("texture-info", [this](const std::string& id) -> sol::object {
            std::optional<std::string> texture_name = browser_system.get_surface_texture_name(id);
            if (!texture_name) {
                return sol::make_object(*lua_state, sol::nil);
            }
            auto it = ResourceManager::textures.find(*texture_name);
            if (it == ResourceManager::textures.end()) {
                return sol::make_object(*lua_state, sol::nil);
            }
            const Texture2D& texture = it->second;
            sol::table table = lua_state->create_table();
            table["name"] = *texture_name;
            table["id"] = static_cast<int>(texture.id);
            table["width"] = texture.width;
            table["height"] = texture.height;
            table["channels"] = texture.n;
            table["ready"] = texture.ready;
            return sol::make_object(*lua_state, table);
        });
        browser_table.set_function("surface-stats", [this](const std::string& id) -> sol::object {
            std::optional<browser::BrowserSystem::SurfaceStats> stats = browser_system.get_surface_stats(id);
            if (!stats) {
                return sol::make_object(*lua_state, sol::nil);
            }
            sol::table table = lua_state->create_table();
            table["exists"] = stats->exists;
            table["visible"] = stats->visible;
            table["texture-allocated"] = stats->texture_allocated;
            table["width"] = static_cast<int>(stats->width);
            table["height"] = static_cast<int>(stats->height);
            table["paint-count"] = static_cast<double>(stats->paint_count);
            table["upload-count"] = static_cast<double>(stats->upload_count);
            table["last-upload-frame"] = static_cast<double>(stats->last_upload_frame);
            return sol::make_object(*lua_state, table);
        });
        browser_table.set_function("list-surfaces", [this]() -> sol::table {
            std::vector<std::string> ids = browser_system.list_surface_ids();
            sol::table out = lua_state->create_table(static_cast<int>(ids.size()), 0);
            int index = 1;
            for (const std::string& id : ids) {
                out[index] = id;
                ++index;
            }
            return out;
        });
        lua_engine["browser"] = browser_table;
    }
    isRunning = true;
    return true;
}

void Engine::run() {
    timer.reset();
    int previous_target_fps = timer.getTargetFps();

    auto dispatch_lua_work = [this]() {
        if (jobs) {
            lua_jobs_dispatch(*lua_state, *jobs);
        }
        lua_http_dispatch(*lua_state);
        lua_process_dispatch(*lua_state);
        lua_http_server_dispatch(*lua_state);
        lua_callbacks_dispatch(*lua_state);
    };

    auto is_window_management_event = [](Uint32 event_type) {
        if (event_type >= SDL_EVENT_WINDOW_FIRST && event_type <= SDL_EVENT_WINDOW_LAST) {
            return true;
        }
        return event_type == SDL_EVENT_QUIT ||
               event_type == SDL_EVENT_WILL_ENTER_BACKGROUND ||
               event_type == SDL_EVENT_DID_ENTER_FOREGROUND;
    };

    auto handle_event = [this, &is_window_management_event](const SDL_Event& event) {
        if (event.type == request_frame_event_type) {
            return;
        }
        if (!window && event.type >= SDL_EVENT_WINDOW_FIRST && event.type <= SDL_EVENT_WINDOW_LAST) {
            return;
        }
        if (input_paused_ && !is_window_management_event(event.type)) {
            return;
        }

        switch (event.type) {
            case SDL_EVENT_QUIT:
                isRunning = false;
                break;

            case SDL_EVENT_WINDOW_RESIZED:
                {
                    Uint64 resize_started = SDL_GetPerformanceCounter();
                    Uint64 perf_frequency = SDL_GetPerformanceFrequency();
                    int width = event.window.data1;
                    int height = event.window.data2;
                    window->updateViewportFromWindowPixels();
                    int pixel_width = width;
                    int pixel_height = height;
                    if (window) {
                        window->getWindowSizeInPixels(pixel_width, pixel_height);
                    }
                    lua_engine["width"] = width;
                    lua_engine["height"] = height;
                    lua_engine["pixel-width"] = pixel_width;
                    lua_engine["pixel-height"] = pixel_height;
                    sol::table payload = lua_state->create_table();
                    payload["width"] = width;
                    payload["height"] = height;
                    payload["pixel-width"] = pixel_width;
                    payload["pixel-height"] = pixel_height;
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("window-resized", payload);
                    Uint64 resize_finished = SDL_GetPerformanceCounter();
                    double resize_ms = 0.0;
                    if (perf_frequency > 0) {
                        resize_ms = (static_cast<double>(resize_finished - resize_started) * 1000.0)
                                    / static_cast<double>(perf_frequency);
                    }
                    LOG(Info) << "window-resized handled in " << resize_ms << "ms"
                              << " (" << width << "x" << height << ")";
                }
                break;

            case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
                {
                    lua_engine["pixel-width"] = event.window.data1;
                    lua_engine["pixel-height"] = event.window.data2;
                    window->updateViewportFromWindowPixels();
                    sol::table payload = lua_state->create_table();
                    payload["width"] = event.window.data1;
                    payload["height"] = event.window.data2;
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("window-pixel-size-changed", payload);
                }
                break;

            case SDL_EVENT_WINDOW_MAXIMIZED:
                {
                    lua_engine["window-mode"] = "maximized";
                    sol::table payload = lua_state->create_table();
                    payload["mode"] = "maximized";
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("window-mode-changed", payload);
                }
                break;

            case SDL_EVENT_WINDOW_RESTORED:
                {
                    lua_engine["window-mode"] = "windowed";
                    sol::table payload = lua_state->create_table();
                    payload["mode"] = "windowed";
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("window-mode-changed", payload);
                    sol::table minimized_payload = lua_state->create_table();
                    minimized_payload["minimized"] = false;
                    minimized_payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("window-minimized-changed", minimized_payload);
                }
                break;

            case SDL_EVENT_WINDOW_MINIMIZED:
                {
                    sol::table payload = lua_state->create_table();
                    payload["minimized"] = true;
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("window-minimized-changed", payload);
                }
                break;

            case SDL_EVENT_WINDOW_HIDDEN:
                {
                    sol::table payload = lua_state->create_table();
                    payload["hidden"] = true;
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("window-hidden-changed", payload);
                }
                break;

            case SDL_EVENT_WINDOW_SHOWN:
                {
                    sol::table payload = lua_state->create_table();
                    payload["hidden"] = false;
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("window-hidden-changed", payload);
                }
                break;

            case SDL_EVENT_WINDOW_OCCLUDED:
                {
                    sol::table payload = lua_state->create_table();
                    payload["occluded"] = true;
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("window-occluded-changed", payload);
                }
                break;

            case SDL_EVENT_WINDOW_EXPOSED:
                {
                    sol::table payload = lua_state->create_table();
                    payload["occluded"] = false;
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("window-occluded-changed", payload);
                }
                break;

            case SDL_EVENT_WINDOW_FOCUS_GAINED:
                {
                    sol::table payload = lua_state->create_table();
                    payload["focused"] = true;
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("window-focus-changed", payload);
                }
                break;

            case SDL_EVENT_WINDOW_FOCUS_LOST:
                {
                    sol::table payload = lua_state->create_table();
                    payload["focused"] = false;
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("window-focus-changed", payload);
                }
                break;

            case SDL_EVENT_WILL_ENTER_BACKGROUND:
                {
                    sol::table payload = lua_state->create_table();
                    payload["suspended"] = true;
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("app-suspended-changed", payload);
                }
                break;

            case SDL_EVENT_DID_ENTER_FOREGROUND:
                {
                    sol::table payload = lua_state->create_table();
                    payload["suspended"] = false;
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("app-suspended-changed", payload);
                }
                break;

            case SDL_EVENT_WINDOW_ENTER_FULLSCREEN:
                {
                    lua_engine["window-mode"] = "fullscreen";
                    sol::table payload = lua_state->create_table();
                    payload["mode"] = "fullscreen";
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("window-mode-changed", payload);
                }
                break;

            case SDL_EVENT_WINDOW_LEAVE_FULLSCREEN:
                {
                    WindowStartupMode current_mode = WindowStartupMode::Windowed;
                    if (window) {
                        current_mode = window->currentStartupMode();
                    }
                    const char* mode = startup_mode_to_string(current_mode);
                    lua_engine["window-mode"] = mode;
                    sol::table payload = lua_state->create_table();
                    payload["mode"] = mode;
                    payload["timestamp"] = ns_to_ms(event.common.timestamp);
                    emit_engine_event("window-mode-changed", payload);
                }
                break;

            case SDL_EVENT_KEY_DOWN: {
                switch(event.key.key) {
                    case SDLK_F11:
                        window->toggleFullscreen();
                        break;

                }
                sol::table payload = lua_state->create_table();
                payload["key"] = static_cast<int>(event.key.key);
                payload["scancode"] = static_cast<int>(event.key.scancode);
                payload["mod"] = static_cast<int>(event.key.mod);
                payload["repeat"] = event.key.repeat != 0;
                payload["timestamp"] = ns_to_ms(event.common.timestamp);
                emit_engine_event("key-down", payload);
                break;
            }

            case SDL_EVENT_KEY_UP: {
                sol::table payload = lua_state->create_table();
                payload["key"] = static_cast<int>(event.key.key);
                payload["scancode"] = static_cast<int>(event.key.scancode);
                payload["mod"] = static_cast<int>(event.key.mod);
                payload["timestamp"] = ns_to_ms(event.common.timestamp);
                emit_engine_event("key-up", payload);
                break;
            }

            case SDL_EVENT_MOUSE_MOTION: {
                if (event.motion.which == SDL_PEN_MOUSEID) {
                    break;
                }
                inputState.mouseState.set_motion(
                    event.motion.x,
                    event.motion.y,
                    event.motion.xrel,
                    event.motion.yrel);
                sol::table payload = lua_state->create_table();
                payload["x"] = event.motion.x;
                payload["y"] = event.motion.y;
                payload["xrel"] = event.motion.xrel;
                payload["yrel"] = event.motion.yrel;
                payload["which"] = static_cast<int>(event.motion.which);
                payload["mod"] = static_cast<int>(SDL_GetModState());
                payload["timestamp"] = ns_to_ms(event.common.timestamp);
                emit_engine_event("mouse-motion", payload);
                break;
            }

            case SDL_EVENT_MOUSE_BUTTON_DOWN: {
                if (event.button.which == SDL_PEN_MOUSEID) {
                    break;
                }
                inputState.mouseState.set_motion(event.button.x, event.button.y, 0.0F, 0.0F);
                inputState.mouseState.set_button(event.button.button, true);
                sol::table payload = lua_state->create_table();
                payload["button"] = static_cast<int>(event.button.button);
                payload["state"] = event.button.down;
                payload["clicks"] = static_cast<int>(event.button.clicks);
                payload["x"] = event.button.x;
                payload["y"] = event.button.y;
                payload["which"] = static_cast<int>(event.button.which);
                payload["mod"] = static_cast<int>(SDL_GetModState());
                payload["timestamp"] = ns_to_ms(event.common.timestamp);
                emit_engine_event("mouse-button-down", payload);
                break;
            }

            case SDL_EVENT_MOUSE_BUTTON_UP: {
                if (event.button.which == SDL_PEN_MOUSEID) {
                    break;
                }
                inputState.mouseState.set_motion(event.button.x, event.button.y, 0.0F, 0.0F);
                inputState.mouseState.set_button(event.button.button, false);
                sol::table payload = lua_state->create_table();
                payload["button"] = static_cast<int>(event.button.button);
                payload["state"] = event.button.down;
                payload["clicks"] = static_cast<int>(event.button.clicks);
                payload["x"] = event.button.x;
                payload["y"] = event.button.y;
                payload["which"] = static_cast<int>(event.button.which);
                payload["mod"] = static_cast<int>(SDL_GetModState());
                payload["timestamp"] = ns_to_ms(event.common.timestamp);
                emit_engine_event("mouse-button-up", payload);
                break;
            }

            case SDL_EVENT_MOUSE_WHEEL: {
                if (event.wheel.which == SDL_PEN_MOUSEID) {
                    break;
                }
                float wheel_x = event.wheel.x;
                float wheel_y = event.wheel.y;
                int wheel_integer_x = event.wheel.integer_x;
                int wheel_integer_y = event.wheel.integer_y;
                if (event.wheel.direction == SDL_MOUSEWHEEL_FLIPPED) {
                    wheel_x = -wheel_x;
                    wheel_y = -wheel_y;
                    wheel_integer_x = -wheel_integer_x;
                    wheel_integer_y = -wheel_integer_y;
                }
                inputState.mouseState.add_wheel(wheel_x, wheel_y);
                sol::table payload = lua_state->create_table();
                payload["x"] = wheel_x;
                payload["y"] = wheel_y;
                payload["direction"] = static_cast<int>(event.wheel.direction);
                payload["which"] = static_cast<int>(event.wheel.which);
                payload["mouse-x"] = event.wheel.mouse_x;
                payload["mouse-y"] = event.wheel.mouse_y;
                payload["integer-x"] = wheel_integer_x;
                payload["integer-y"] = wheel_integer_y;
                payload["mod"] = static_cast<int>(SDL_GetModState());
                payload["timestamp"] = ns_to_ms(event.common.timestamp);
                emit_engine_event("mouse-wheel", payload);
                break;
            }

            case SDL_EVENT_FINGER_DOWN: {
                log_touch_event(event, "received");
                if (event.tfinger.touchID == SDL_PEN_TOUCHID) {
                    log_touch_event(event, "ignored-pen-touch");
                    break;
                }
                inputState.on_touch_down(event.tfinger.touchID,
                                         event.tfinger.fingerID,
                                         event.tfinger.x,
                                         event.tfinger.y,
                                         event.tfinger.dx,
                                         event.tfinger.dy,
                                         event.tfinger.pressure,
                                         ns_to_ms(event.common.timestamp));
                const auto [window_x, window_y] =
                    touch_window_coordinates(lua_engine, window.get(), event.tfinger.x, event.tfinger.y);
                const auto [window_dx, window_dy] =
                    touch_window_coordinates(lua_engine, window.get(), event.tfinger.dx, event.tfinger.dy);
                sol::table payload = lua_state->create_table();
                payload["touch-id"] = static_cast<lua_Integer>(event.tfinger.touchID);
                payload["finger-id"] = static_cast<lua_Integer>(event.tfinger.fingerID);
                payload["x"] = window_x;
                payload["y"] = window_y;
                payload["xrel"] = window_dx;
                payload["yrel"] = window_dy;
                payload["normalized-x"] = event.tfinger.x;
                payload["normalized-y"] = event.tfinger.y;
                payload["dx"] = event.tfinger.dx;
                payload["dy"] = event.tfinger.dy;
                payload["pressure"] = event.tfinger.pressure;
                payload["window-id"] = static_cast<int>(event.tfinger.windowID);
                payload["timestamp"] = ns_to_ms(event.common.timestamp);
                emit_engine_event("touch-down", payload);
                break;
            }

            case SDL_EVENT_FINGER_MOTION: {
                log_touch_event(event, "received");
                if (event.tfinger.touchID == SDL_PEN_TOUCHID) {
                    log_touch_event(event, "ignored-pen-touch");
                    break;
                }
                inputState.on_touch_motion(event.tfinger.touchID,
                                           event.tfinger.fingerID,
                                           event.tfinger.x,
                                           event.tfinger.y,
                                           event.tfinger.dx,
                                           event.tfinger.dy,
                                           event.tfinger.pressure,
                                           ns_to_ms(event.common.timestamp));
                const auto [window_x, window_y] =
                    touch_window_coordinates(lua_engine, window.get(), event.tfinger.x, event.tfinger.y);
                const auto [window_dx, window_dy] =
                    touch_window_coordinates(lua_engine, window.get(), event.tfinger.dx, event.tfinger.dy);
                sol::table payload = lua_state->create_table();
                payload["touch-id"] = static_cast<lua_Integer>(event.tfinger.touchID);
                payload["finger-id"] = static_cast<lua_Integer>(event.tfinger.fingerID);
                payload["x"] = window_x;
                payload["y"] = window_y;
                payload["xrel"] = window_dx;
                payload["yrel"] = window_dy;
                payload["normalized-x"] = event.tfinger.x;
                payload["normalized-y"] = event.tfinger.y;
                payload["dx"] = event.tfinger.dx;
                payload["dy"] = event.tfinger.dy;
                payload["pressure"] = event.tfinger.pressure;
                payload["window-id"] = static_cast<int>(event.tfinger.windowID);
                payload["timestamp"] = ns_to_ms(event.common.timestamp);
                emit_engine_event("touch-motion", payload);
                break;
            }

            case SDL_EVENT_FINGER_UP: {
                log_touch_event(event, "received");
                if (event.tfinger.touchID == SDL_PEN_TOUCHID) {
                    log_touch_event(event, "ignored-pen-touch");
                    break;
                }
                inputState.on_touch_up(event.tfinger.touchID,
                                       event.tfinger.fingerID,
                                       event.tfinger.x,
                                       event.tfinger.y,
                                       event.tfinger.dx,
                                       event.tfinger.dy,
                                       event.tfinger.pressure,
                                       ns_to_ms(event.common.timestamp));
                const auto [window_x, window_y] =
                    touch_window_coordinates(lua_engine, window.get(), event.tfinger.x, event.tfinger.y);
                const auto [window_dx, window_dy] =
                    touch_window_coordinates(lua_engine, window.get(), event.tfinger.dx, event.tfinger.dy);
                sol::table payload = lua_state->create_table();
                payload["touch-id"] = static_cast<lua_Integer>(event.tfinger.touchID);
                payload["finger-id"] = static_cast<lua_Integer>(event.tfinger.fingerID);
                payload["x"] = window_x;
                payload["y"] = window_y;
                payload["xrel"] = window_dx;
                payload["yrel"] = window_dy;
                payload["normalized-x"] = event.tfinger.x;
                payload["normalized-y"] = event.tfinger.y;
                payload["dx"] = event.tfinger.dx;
                payload["dy"] = event.tfinger.dy;
                payload["pressure"] = event.tfinger.pressure;
                payload["window-id"] = static_cast<int>(event.tfinger.windowID);
                payload["timestamp"] = ns_to_ms(event.common.timestamp);
                emit_engine_event("touch-up", payload);
                break;
            }

            case SDL_EVENT_FINGER_CANCELED: {
                log_touch_event(event, "received");
                if (event.tfinger.touchID == SDL_PEN_TOUCHID) {
                    log_touch_event(event, "ignored-pen-touch");
                    break;
                }
                inputState.on_touch_up(event.tfinger.touchID,
                                       event.tfinger.fingerID,
                                       event.tfinger.x,
                                       event.tfinger.y,
                                       event.tfinger.dx,
                                       event.tfinger.dy,
                                       event.tfinger.pressure,
                                       ns_to_ms(event.common.timestamp));
                const auto [window_x, window_y] =
                    touch_window_coordinates(lua_engine, window.get(), event.tfinger.x, event.tfinger.y);
                const auto [window_dx, window_dy] =
                    touch_window_coordinates(lua_engine, window.get(), event.tfinger.dx, event.tfinger.dy);
                sol::table payload = lua_state->create_table();
                payload["touch-id"] = static_cast<lua_Integer>(event.tfinger.touchID);
                payload["finger-id"] = static_cast<lua_Integer>(event.tfinger.fingerID);
                payload["x"] = window_x;
                payload["y"] = window_y;
                payload["xrel"] = window_dx;
                payload["yrel"] = window_dy;
                payload["normalized-x"] = event.tfinger.x;
                payload["normalized-y"] = event.tfinger.y;
                payload["dx"] = event.tfinger.dx;
                payload["dy"] = event.tfinger.dy;
                payload["pressure"] = event.tfinger.pressure;
                payload["window-id"] = static_cast<int>(event.tfinger.windowID);
                payload["timestamp"] = ns_to_ms(event.common.timestamp);
                payload["canceled"] = true;
                emit_engine_event("touch-canceled", payload);
                break;
            }

            case SDL_EVENT_PEN_PROXIMITY_IN: {
                inputState.on_pen_proximity_in(event.pproximity.which,
                                               ns_to_ms(event.common.timestamp));
                const InputState::PenState* pen = inputState.pen_by_id(event.pproximity.which);
                sol::table payload = make_pen_payload(*lua_state,
                                                      pen,
                                                      event.pproximity.which,
                                                      pen ? pen->inputState : 0,
                                                      pen ? pen->x : 0.0F,
                                                      pen ? pen->y : 0.0F,
                                                      ns_to_ms(event.common.timestamp));
                payload["window-id"] = static_cast<int>(event.pproximity.windowID);
                emit_engine_event("pen-proximity-in", payload);
                break;
            }

            case SDL_EVENT_PEN_PROXIMITY_OUT: {
                inputState.on_pen_proximity_out(event.pproximity.which,
                                                ns_to_ms(event.common.timestamp));
                const InputState::PenState* pen = inputState.pen_by_id(event.pproximity.which);
                sol::table payload = make_pen_payload(*lua_state,
                                                      pen,
                                                      event.pproximity.which,
                                                      pen ? pen->inputState : 0,
                                                      pen ? pen->x : 0.0F,
                                                      pen ? pen->y : 0.0F,
                                                      ns_to_ms(event.common.timestamp));
                payload["window-id"] = static_cast<int>(event.pproximity.windowID);
                emit_engine_event("pen-proximity-out", payload);
                break;
            }

            case SDL_EVENT_PEN_MOTION: {
                inputState.on_pen_motion(event.pmotion.which,
                                         event.pmotion.x,
                                         event.pmotion.y,
                                         event.pmotion.pen_state,
                                         ns_to_ms(event.common.timestamp));
                const InputState::PenState* pen = inputState.pen_by_id(event.pmotion.which);
                sol::table payload = make_pen_payload(*lua_state,
                                                      pen,
                                                      event.pmotion.which,
                                                      event.pmotion.pen_state,
                                                      event.pmotion.x,
                                                      event.pmotion.y,
                                                      ns_to_ms(event.common.timestamp));
                payload["window-id"] = static_cast<int>(event.pmotion.windowID);
                emit_engine_event("pen-motion", payload);
                break;
            }

            case SDL_EVENT_PEN_DOWN: {
                inputState.on_pen_down(event.ptouch.which,
                                       event.ptouch.x,
                                       event.ptouch.y,
                                       event.ptouch.eraser,
                                       event.ptouch.pen_state,
                                       ns_to_ms(event.common.timestamp));
                const InputState::PenState* pen = inputState.pen_by_id(event.ptouch.which);
                sol::table payload = make_pen_payload(*lua_state,
                                                      pen,
                                                      event.ptouch.which,
                                                      event.ptouch.pen_state,
                                                      event.ptouch.x,
                                                      event.ptouch.y,
                                                      ns_to_ms(event.common.timestamp));
                payload["window-id"] = static_cast<int>(event.ptouch.windowID);
                payload["eraser"] = event.ptouch.eraser;
                emit_engine_event("pen-down", payload);
                break;
            }

            case SDL_EVENT_PEN_UP: {
                inputState.on_pen_up(event.ptouch.which,
                                     event.ptouch.x,
                                     event.ptouch.y,
                                     event.ptouch.eraser,
                                     event.ptouch.pen_state,
                                     ns_to_ms(event.common.timestamp));
                const InputState::PenState* pen = inputState.pen_by_id(event.ptouch.which);
                sol::table payload = make_pen_payload(*lua_state,
                                                      pen,
                                                      event.ptouch.which,
                                                      event.ptouch.pen_state,
                                                      event.ptouch.x,
                                                      event.ptouch.y,
                                                      ns_to_ms(event.common.timestamp));
                payload["window-id"] = static_cast<int>(event.ptouch.windowID);
                payload["eraser"] = event.ptouch.eraser;
                emit_engine_event("pen-up", payload);
                break;
            }

            case SDL_EVENT_PEN_BUTTON_DOWN: {
                inputState.on_pen_button(event.pbutton.which,
                                         event.pbutton.x,
                                         event.pbutton.y,
                                         event.pbutton.button,
                                         true,
                                         event.pbutton.pen_state,
                                         ns_to_ms(event.common.timestamp));
                const InputState::PenState* pen = inputState.pen_by_id(event.pbutton.which);
                sol::table payload = make_pen_payload(*lua_state,
                                                      pen,
                                                      event.pbutton.which,
                                                      event.pbutton.pen_state,
                                                      event.pbutton.x,
                                                      event.pbutton.y,
                                                      ns_to_ms(event.common.timestamp));
                payload["window-id"] = static_cast<int>(event.pbutton.windowID);
                payload["button"] = static_cast<int>(event.pbutton.button);
                payload["state"] = true;
                emit_engine_event("pen-button-down", payload);
                break;
            }

            case SDL_EVENT_PEN_BUTTON_UP: {
                inputState.on_pen_button(event.pbutton.which,
                                         event.pbutton.x,
                                         event.pbutton.y,
                                         event.pbutton.button,
                                         false,
                                         event.pbutton.pen_state,
                                         ns_to_ms(event.common.timestamp));
                const InputState::PenState* pen = inputState.pen_by_id(event.pbutton.which);
                sol::table payload = make_pen_payload(*lua_state,
                                                      pen,
                                                      event.pbutton.which,
                                                      event.pbutton.pen_state,
                                                      event.pbutton.x,
                                                      event.pbutton.y,
                                                      ns_to_ms(event.common.timestamp));
                payload["window-id"] = static_cast<int>(event.pbutton.windowID);
                payload["button"] = static_cast<int>(event.pbutton.button);
                payload["state"] = false;
                emit_engine_event("pen-button-up", payload);
                break;
            }

            case SDL_EVENT_PEN_AXIS: {
                inputState.on_pen_axis(event.paxis.which,
                                       event.paxis.x,
                                       event.paxis.y,
                                       event.paxis.axis,
                                       event.paxis.value,
                                       event.paxis.pen_state,
                                       ns_to_ms(event.common.timestamp));
                const InputState::PenState* pen = inputState.pen_by_id(event.paxis.which);
                sol::table payload = make_pen_payload(*lua_state,
                                                      pen,
                                                      event.paxis.which,
                                                      event.paxis.pen_state,
                                                      event.paxis.x,
                                                      event.paxis.y,
                                                      ns_to_ms(event.common.timestamp));
                payload["window-id"] = static_cast<int>(event.paxis.windowID);
                payload["axis"] = static_cast<int>(event.paxis.axis);
                payload["value"] = event.paxis.value;
                emit_engine_event("pen-axis", payload);
                break;
            }

            case SDL_EVENT_TEXT_INPUT: {
                sol::table payload = lua_state->create_table();
                payload["text"] = std::string(event.text.text);
                payload["timestamp"] = ns_to_ms(event.common.timestamp);
                emit_engine_event("text-input", payload);
                break;
            }

            case SDL_EVENT_TEXT_EDITING: {
                sol::table payload = lua_state->create_table();
                payload["text"] = std::string(event.edit.text);
                payload["start"] = static_cast<int>(event.edit.start);
                payload["length"] = static_cast<int>(event.edit.length);
                payload["timestamp"] = ns_to_ms(event.common.timestamp);
                emit_engine_event("text-editing", payload);
                break;
            }

            case SDL_EVENT_GAMEPAD_BUTTON_DOWN: {
                inputState.on_gamepad_button(event.gbutton.button, true, event.gbutton.which, ns_to_ms(event.common.timestamp));
                sol::table payload = lua_state->create_table();
                payload["which"] = static_cast<int>(event.gbutton.which);
                payload["instance-id"] = static_cast<int>(event.gbutton.which);
                payload["button"] = static_cast<int>(event.gbutton.button);
                payload["state"] = event.gbutton.down;
                payload["timestamp"] = ns_to_ms(event.common.timestamp);
                emit_engine_event("gamepad-button-down", payload);
                break;
            }

            case SDL_EVENT_GAMEPAD_BUTTON_UP: {
                inputState.on_gamepad_button(event.gbutton.button, false, event.gbutton.which, ns_to_ms(event.common.timestamp));
                sol::table payload = lua_state->create_table();
                payload["which"] = static_cast<int>(event.gbutton.which);
                payload["instance-id"] = static_cast<int>(event.gbutton.which);
                payload["button"] = static_cast<int>(event.gbutton.button);
                payload["state"] = event.gbutton.down;
                payload["timestamp"] = ns_to_ms(event.common.timestamp);
                emit_engine_event("gamepad-button-up", payload);
                break;
            }

            case SDL_EVENT_GAMEPAD_AXIS_MOTION: {
                const float axis_value = static_cast<float>(event.gaxis.value) / 32768.0f;
                inputState.on_gamepad_axis(event.gaxis.axis, axis_value, event.gaxis.which, ns_to_ms(event.common.timestamp));
                sol::table payload = lua_state->create_table();
                payload["which"] = static_cast<int>(event.gaxis.which);
                payload["instance-id"] = static_cast<int>(event.gaxis.which);
                payload["axis"] = static_cast<int>(event.gaxis.axis);
                payload["value"] = axis_value;
                payload["timestamp"] = ns_to_ms(event.common.timestamp);
                emit_engine_event("gamepad-axis-motion", payload);
                if (inputDialType) {
                    inputDialType->process_gamepad(event.gaxis.which);
                }
                break;
            }

            case SDL_EVENT_GAMEPAD_ADDED: {
                const SDL_JoystickID instance_id = openGamepad(event.gdevice.which, ns_to_ms(event.common.timestamp));
                sol::table payload = lua_state->create_table();
                payload["which"] = static_cast<int>(event.gdevice.which);
                payload["instance-id"] = static_cast<int>(instance_id);
                payload["timestamp"] = ns_to_ms(event.common.timestamp);
                emit_engine_event("gamepad-added", payload);
                break;
            }

            case SDL_EVENT_GAMEPAD_REMOVED: {
                closeGamepad(event.gdevice.which, ns_to_ms(event.common.timestamp));
                sol::table payload = lua_state->create_table();
                payload["which"] = static_cast<int>(event.gdevice.which);
                payload["instance-id"] = static_cast<int>(event.gdevice.which);
                payload["timestamp"] = ns_to_ms(event.common.timestamp);
                emit_engine_event("gamepad-removed", payload);
                break;
            }

            default:
                break;
        }
    };

    while (isRunning) {
        cef_runtime::do_message_loop_work();
        const int target_fps = timer.getTargetFps();
        const bool zero_fps_mode = target_fps <= 0;
        if (!zero_fps_mode && previous_target_fps <= 0) {
            timer.reset();
        }

        SDL_Event first_event {};
        bool has_first_event = false;
        bool has_force_ui_frame = false;
        if (zero_fps_mode) {
            has_first_event = SDL_WaitEventTimeout(&first_event, 100) == 1;
            if (!has_first_event) {
                dispatch_lua_work();
                previous_target_fps = target_fps;
                continue;
            }
            has_force_ui_frame = first_event.type == request_frame_event_type;
            dt = 0;
        } else {
            dt = timer.computeDeltaTime();
        }

        std::memcpy(inputState.keyboardState.previousValue,
                    inputState.keyboardState.currentValue,
                    SDL_SCANCODE_COUNT);
        inputState.mouseState.begin_frame();
        inputState.begin_frame();
        if (!input_paused_ && window) {
            float mouseX = static_cast<float>(inputState.mouseState.x);
            float mouseY = static_cast<float>(inputState.mouseState.y);
            SDL_MouseButtonFlags mouseMask = SDL_GetMouseState(&mouseX, &mouseY);
            inputState.mouseState.update_from_mask(mouseMask);
            inputState.mouseState.set_motion(mouseX, mouseY, 0.0F, 0.0F);
        }

        if (has_first_event) {
            handle_event(first_event);
        }

        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == request_frame_event_type) {
                has_force_ui_frame = true;
            }
            handle_event(event);
        }

        if (!isRunning) {
            previous_target_fps = target_fps;
            continue;
        }

        Uint64 now_ticks = SDL_GetTicks();
        if (!on_battery_known_ || now_ticks >= next_power_poll_ticks_) {
            int seconds_left = -1;
            int percent = -1;
            SDL_PowerState power_state = SDL_GetPowerInfo(&seconds_left, &percent);
            const bool on_battery = is_on_battery(power_state);
            if (!on_battery_known_ || on_battery != on_battery_state_) {
                on_battery_state_ = on_battery;
                on_battery_known_ = true;
                sol::table payload = lua_state->create_table();
                payload["on_battery"] = on_battery;
                payload["state"] = power_state_to_string(power_state);
                payload["seconds_left"] = seconds_left;
                payload["percent"] = percent;
                payload["timestamp"] = now_ticks;
                emit_engine_event("on-battery-changed", payload);
            }
            next_power_poll_ticks_ = now_ticks + 1000;
        }

        bool has_active_video = video_manager.has_active_playback();
        if (has_active_video != video_playback_active_) {
            video_playback_active_ = has_active_video;
            sol::table payload = lua_state->create_table();
            payload["active"] = has_active_video;
            payload["timestamp"] = now_ticks;
            emit_engine_event("video-playback-active-changed", payload);
        }

        if (!physics_paused_) {
            physics.update(static_cast<uint32_t>(dt));
        }

        audio.update(static_cast<uint32_t>(dt));
        video_manager.update_all(static_cast<uint32_t>(dt));

        if (jobs) {
            ResourceManager::processTextureJobs();
            ResourceManager::processAudioJobs();
        }

        if (window) {
            browser_system.tick(frame_id.load(std::memory_order_relaxed));
        }

        lua_engine["frame-id"] = frame_id.load(std::memory_order_relaxed);
        dispatch_lua_work();
        {
            sol::table payload = lua_state->create_table();
            payload["dt"] = static_cast<uint32_t>(dt);
            payload["frame-id"] = frame_id.load(std::memory_order_relaxed);
            emit_engine_event("engine-tick", payload);
        }
        const bool render_enabled = headless_mode_ || !ui_paused_ || has_force_ui_frame;
        if (render_enabled) {
            if (window) {
                window->updateFpsCounter(dt);
                window->clear();
            }
            {
                sol::table events = lua_engine["events"];
                sol::table signal = events["updated"];
                sol::function emit = signal["emit"];
                fennel_call_fatal(emit, static_cast<uint32_t>(dt));
            }
            frame_id.fetch_add(1, std::memory_order_relaxed);
            if (window) {
                window->swapBuffer();
            }
        }

        if (!zero_fps_mode) {
            timer.delayTime();
        }
        previous_target_fps = target_fps;
    }
}

SDL_JoystickID Engine::openGamepad(SDL_JoystickID instanceId, Uint64 timestamp)
{
    if (!SDL_IsGamepad(instanceId)) {
        return 0;
    }

    SDL_Gamepad* gamepad = SDL_OpenGamepad(instanceId);
    if (!gamepad) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Failed to open gamepad %" SDL_PRIu32 ": %s",
                    instanceId,
                    SDL_GetError());
        return 0;
    }

    SDL_Joystick* joystick = SDL_GetGamepadJoystick(gamepad);
    if (!joystick) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Failed to get joystick handle for gamepad %" SDL_PRIu32 ": %s",
                    instanceId,
                    SDL_GetError());
        SDL_CloseGamepad(gamepad);
        return 0;
    }

    const SDL_JoystickID instance_id = SDL_GetJoystickID(joystick);
    auto existing = gamepads.find(instance_id);
    if (existing != gamepads.end()) {
        SDL_CloseGamepad(existing->second);
    }
    gamepads[instance_id] = gamepad;
    inputState.on_gamepad_connected(static_cast<Sint32>(instance_id), instance_id, timestamp);
    return instance_id;
}

void Engine::closeGamepad(SDL_JoystickID instanceId, Uint64 timestamp)
{
    if (inputDialType) {
        inputDialType->deactivate_gamepad(instanceId);
    }
    auto it = gamepads.find(instanceId);
    if (it != gamepads.end()) {
        if (it->second) {
            SDL_CloseGamepad(it->second);
        }
        gamepads.erase(it);
    }
    inputState.on_gamepad_disconnected(instanceId, timestamp);
}

void Engine::closeAllGamepads(Uint64 timestamp)
{
    std::vector<SDL_JoystickID> instance_ids;
    instance_ids.reserve(gamepads.size());
    for (const auto& [instance_id, gamepad] : gamepads) {
        (void)gamepad;
        instance_ids.push_back(instance_id);
    }
    for (const SDL_JoystickID instance_id : instance_ids) {
        closeGamepad(instance_id, timestamp);
    }
}

void Engine::shutdown() {
    browser_system.shutdown();
    inputDialType.reset();
    closeAllGamepads(SDL_GetTicks());
    lua_jobs_clear_callbacks();
    lua_keyring_drop(*lua_state);
    lua_process_drop(*lua_state);
    lua_http_server_shutdown_all();
    lua_callbacks_shutdown();
    video_manager.drop_all();
    video_manager.set_audio(nullptr);
    lua_video_set_manager(*lua_state, nullptr);
    ResourceManager::clearPending();
    ResourceManager::clear();
    log_set_frame_id_provider(nullptr);
    if (jobs) {
        jobs->shutdown();
    }
    shutdownSystemCursors();
    setScreensaverInhibited(false);
    if (window) {
        window->clean();
    }
    if (sdl_headless_initialized_) {
        SDL_Quit();
        sdl_headless_initialized_ = false;
    }
}

void Engine::emit_engine_event(const std::string& signal_name, sol::table payload) {
    sol::object events_obj = lua_engine["events"];
    //if (!events_obj.valid() || !events_obj.is<sol::table>()) {
    //    return;
    //}

    sol::table events = events_obj.as<sol::table>();
    sol::object signal_obj = events[signal_name];
    //if (!signal_obj.valid() || !signal_obj.is<sol::table>()) {
    //    return;
    //}

    sol::table signal = signal_obj.as<sol::table>();
    sol::object emit_obj = signal["emit"];
    //if (!emit_obj.is<sol::function>()) {
    //    return;
    //}

    sol::function emit = emit_obj.as<sol::function>();
    fennel_call_fatal(emit, payload);
}

void Engine::initSystemCursors() {
    shutdownSystemCursors();

    struct CursorDesc {
        const char* name;
        SDL_SystemCursor type;
    };

    static const CursorDesc cursorDescs[] = {
        {"arrow", SDL_SYSTEM_CURSOR_DEFAULT},
        {"hand", SDL_SYSTEM_CURSOR_POINTER},
        {"ibeam", SDL_SYSTEM_CURSOR_TEXT},
    };

    for (const auto& desc : cursorDescs) {
        SDL_Cursor* cursor = SDL_CreateSystemCursor(desc.type);
        if (!cursor) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "Failed to create system cursor '%s': %s",
                        desc.name,
                        SDL_GetError());
            continue;
        }
        systemCursors[desc.name] = cursor;
    }

    activeCursor = nullptr;
}

void Engine::shutdownSystemCursors() {
    for (auto& pair : systemCursors) {
        if (pair.second) {
            SDL_DestroyCursor(pair.second);
        }
    }
    systemCursors.clear();
    activeCursor = nullptr;
}

void Engine::setSystemCursor(const std::string& name) {
    auto it = systemCursors.find(name);
    if (it == systemCursors.end()) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Attempted to set unknown system cursor '%s'",
                    name.c_str());
        return;
    }

    SDL_Cursor* cursor = it->second;
    if (!cursor || cursor == activeCursor) {
        return;
    }

    SDL_SetCursor(cursor);
    activeCursor = cursor;
}

void Engine::setTextInputEnabled(bool enabled)
{
    if (!window) {
        return;
    }
    if (window->isTextInputEnabled() == enabled) {
        return;
    }
    window->setTextInputEnabled(enabled);
}

bool Engine::setScreensaverInhibited(bool inhibited)
{
    if (!window) {
        if (!inhibited) {
            return true;
        }
        LOG(Warning) << "Cannot inhibit screensaver without an SDL window";
        return false;
    }
    if (screensaver_inhibited_ == inhibited) {
        return true;
    }

    bool ok = inhibited ? SDL_DisableScreenSaver() : SDL_EnableScreenSaver();
    if (!ok) {
        LOG(Warning) << "Failed to "
                     << (inhibited ? "disable" : "enable")
                     << " SDL screensaver: " << SDL_GetError();
        SDL_ClearError();
        return false;
    }

    screensaver_inhibited_ = inhibited;
    lua_engine["screensaver-inhibited"] = screensaver_inhibited_;
    return true;
}
