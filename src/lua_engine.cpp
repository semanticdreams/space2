#include "lua_engine.h"

#include <chrono>
#include <memory>

#include "engine.h"
#include "lua_ray_box.h"
#include "asset_manager.h"

namespace {

struct EngineHandle {
    EngineHandle(sol::state& lua_ref, sol::table engine_table_ref, const EngineConfig& config_ref)
        : lua_state(&lua_ref)
        , engine_table(engine_table_ref)
        , config(config_ref)
    {
    }

    bool start()
    {
        if (started || shutdown) {
            return started;
        }
        started = engine.start(*lua_state, engine_table, config);
        return started;
    }

    void run()
    {
        if (!started || shutdown) {
            return;
        }
        engine.run();
    }

    void shutdown_engine()
    {
        if (!started || shutdown) {
            return;
        }
        shutdown = true;
        engine.shutdown();
    }

    bool is_started() const { return started; }
    bool is_shutdown() const { return shutdown; }

private:
    Engine engine;
    sol::state* lua_state;
    sol::table engine_table;
    EngineConfig config;
    bool started { false };
    bool shutdown { false };
};

EngineConfig parse_engine_config(const sol::object& options)
{
    EngineConfig config;
    if (options.is<sol::table>()) {
        sol::table opts = options.as<sol::table>();
        sol::optional<bool> headless = opts["headless"];
        if (headless) {
            config.headless = *headless;
        }
        sol::optional<int> width = opts["width"];
        if (width && *width > 0) {
            config.width = *width;
        }
        sol::optional<int> height = opts["height"];
        if (height && *height > 0) {
            config.height = *height;
        }
        sol::optional<std::string> title = opts["title"];
        if (title) {
            if (title->empty()) {
                throw sol::error("engine.Engine options.title must be a non-empty string");
            }
            config.title = *title;
        }
        sol::optional<std::string> window_mode = opts["window-mode"];
        if (window_mode) {
            if (*window_mode == "windowed") {
                config.window_mode = WindowStartupMode::Windowed;
            } else if (*window_mode == "maximized") {
                config.window_mode = WindowStartupMode::Maximized;
            } else if (*window_mode == "fullscreen") {
                config.window_mode = WindowStartupMode::Fullscreen;
            } else {
                throw sol::error("engine.Engine options.window-mode must be one of: windowed, maximized, fullscreen");
            }
        }
    }
    return config;
}

std::weak_ptr<EngineHandle> active_engine;

} // namespace

void lua_bind_engine(sol::state& lua)
{
    sol::table engine_module = lua.create_table();
    lua["package"]["preload"]["engine"] = [engine_module](sol::this_state ts) mutable -> sol::object {
        sol::state_view lua_view(ts);
        return sol::make_object(lua_view, engine_module);
    };
    engine_module.set_function("Engine", [&lua](sol::this_state ts, sol::object options) {
        sol::state_view lua_view(ts);
        sol::function require = lua_view["require"];
        sol::table events = require("engine-events");
        sol::table engine_table = lua_view.create_table();
        engine_table["events"] = events;
        engine_table["frame-id"] = static_cast<uint64_t>(0);
        engine_table.set_function("get-asset-path", &AssetManager::getAssetPath);
        EngineConfig config = parse_engine_config(options);
        auto handle = std::make_shared<EngineHandle>(lua, engine_table, config);
        active_engine = handle;

        engine_table.set_function("now-ms", [](sol::object) {
            const auto now = std::chrono::steady_clock::now().time_since_epoch();
            return std::chrono::duration<double, std::milli>(now).count();
        });
        engine_table.set_function("start", [handle](sol::object) { return handle->start(); });
        engine_table.set_function("run", [handle](sol::object) { handle->run(); });
        engine_table.set_function("shutdown", [handle](sol::object) { handle->shutdown_engine(); });
        engine_table.set_function("is-started", [handle](sol::object) { return handle->is_started(); });
        engine_table.set_function("is-shutdown", [handle](sol::object) { return handle->is_shutdown(); });
        return engine_table;
    });
}

bool lua_engine_has_active()
{
    auto handle = active_engine.lock();
    return handle && handle->is_started() && !handle->is_shutdown();
}

void lua_engine_shutdown_active()
{
    auto handle = active_engine.lock();
    if (handle && handle->is_started() && !handle->is_shutdown()) {
        handle->shutdown_engine();
    }
}
