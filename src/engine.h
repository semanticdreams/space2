#pragma once

#include <atomic>
#include <cstdint>
#include <iostream>
#include <memory>
#include <string>
#include <unordered_map>

//#include <pybind11/pybind11.h>
//#include <pybind11/embed.h>

#define SOL_ALL_SAFETIES_ON 1  // optional, extra safety checks
#include <sol/sol.hpp>

#include "window_sdl.h"
#include "timer.h"
#include "input_state.h"
#include "input_dial_type.h"
#include "physics.h"
#include "audio.h"
#include "job_system.h"
#include "keyring.h"
#include "video_player.h"
#include "browser_system.h"

//namespace py = pybind11;

struct EngineConfig {
    bool headless { false };
    int width { 0 };
    int height { 0 };
    std::string title { "space" };
    WindowStartupMode window_mode { WindowStartupMode::Maximized };
};

class Engine {
public:
    Engine();
    bool start(sol::state& lua, sol::table engine_table, const EngineConfig& config);
    void run();
    void shutdown();

    template<typename... Args>
    void fennel_call_fatal(sol::function fn, Args&&... args) {
        if (!lua_state) {
            std::cerr << "Lua state not initialized\n";
            std::abort();
        }
        sol::protected_function pf = fn;

        pf.set_error_handler((*lua_state)["__FENNEL_FATAL_TRACEBACK"]);

        sol::protected_function_result res =
            pf(std::forward<Args>(args)...);

        if (!res.valid()) {
            std::cerr << "Unreachable: fatal call returned after error\n";
            std::abort();
        }
    }

    std::unique_ptr<WindowSdl> window { nullptr };

    void quit() { isRunning = false; };

private:
    bool isRunning { false };

    // Delta time
    Uint64 dt {0};
    std::atomic<uint64_t> frame_id {0};

    std::string title;
    const int screenWidth = 450;
    const int screenHeight = 680;
    Timer timer;

    InputState inputState {};
    std::unique_ptr<InputDialType> inputDialType;
    [[nodiscard]] const InputState& getState() const;

    Physics physics;
    Audio audio;
    VideoManager video_manager;
    std::unique_ptr<JobSystem> jobs;
    Keyring keyring;
    browser::BrowserSystem browser_system;

    // lua
    sol::state* lua_state { nullptr };
    sol::table lua_engine;

    void emit_engine_event(const std::string& signal_name, sol::table payload);
    void initSystemCursors();
    void shutdownSystemCursors();
    void setSystemCursor(const std::string& name);
    SDL_JoystickID openGamepad(SDL_JoystickID instanceId, Uint64 timestamp);
    void closeGamepad(SDL_JoystickID instanceId, Uint64 timestamp);
    void closeAllGamepads(Uint64 timestamp);
    void setTextInputEnabled(bool enabled);
    bool setScreensaverInhibited(bool inhibited);

    std::unordered_map<std::string, SDL_Cursor*> systemCursors;
    std::unordered_map<SDL_JoystickID, SDL_Gamepad*> gamepads;
    SDL_Cursor* activeCursor { nullptr };
    Uint32 request_frame_event_type { static_cast<Uint32>(-1) };
    bool on_battery_state_ { false };
    bool on_battery_known_ { false };
    Uint64 next_power_poll_ticks_ { 0 };
    bool video_playback_active_ { false };
    bool physics_paused_ { false };
    bool input_paused_ { false };
    bool ui_paused_ { false };
    bool screensaver_inhibited_ { false };
    bool sdl_headless_initialized_ { false };
    bool headless_mode_ { false };

    // python
    //std::unique_ptr<py::scoped_interpreter> python;
    //py::object pythonWorld;
};
