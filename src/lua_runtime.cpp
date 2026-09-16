#include "lua_runtime.h"

#include <cstdlib>
#include <iostream>
#include <memory>

#include "asset_manager.h"
#include "http_client.h"
#include "lua_callbacks.h"
#include "lua_engine.h"
#include "lua_http.h"
#include "lua_http_server.h"
#include "lua_ray_box.h"
#include "lua_notify.h"
#include "lua_tray.h"
#include "lua_video.h"
#include "lua_webbrowser.h"
#include "lua_gccjit.h"
#include "lua_xapian.h"
#include "log.h"
#if defined(SPACE_ENABLE_WALLET_CORE)
#include "lua_wallet_core.h"
#endif

extern "C" int luaopen_lsqlite3(lua_State* L);

namespace
{
std::string make_fennel_asset_search_path(const std::string& lua_path)
{
    return lua_path + "/?.fnl;" + lua_path + "/?/init.fnl";
}
}

void lua_bind_opengl(sol::state&);
void lua_bind_image_io(sol::state&);
void lua_bind_json(sol::state&);
void lua_bind_toml(sol::state&);
void lua_bind_shaders(sol::state&);
void lua_bind_textures(sol::state&);
void lua_bind_glm(sol::state&);
void lua_bind_vector_buffer(sol::state&);
void lua_bind_graph_edge_batch(sol::state&);
void lua_bind_tree_sitter(sol::state&);
void lua_bind_msdf_atlas_gen(sol::state&);
void lua_bind_cgltf(sol::state&);
void lua_bind_fs(sol::state&);
void lua_bind_appdirs(sol::state&);
void lua_bind_random(sol::state&);
void lua_bind_physics(sol::state&);
void lua_bind_force_layout(sol::state&);
void lua_bind_colors(sol::state&);
void lua_bind_audio(sol::state&);
void lua_bind_file_watch(sol::state&);
void lua_bind_audio_input(sol::state&);
void lua_bind_aubio(sol::state&);
#if defined(SPACE_HAS_VTERM)
void lua_bind_terminal(sol::state&);
#endif
void lua_bind_input_state(sol::state&);
void lua_bind_zmq(sol::state&);
void lua_bind_matrix(sol::state&);
void lua_bind_realtime(sol::state&);
void lua_bind_logging(sol::state&);
void lua_bind_error_reporting(sol::state&);
void lua_bind_uuid(sol::state&);
void lua_bind_shell(sol::state&);
void lua_bind_process(sol::state&);
void lua_bind_gccjit(sol::state&);
void lua_bind_sysinfo(sol::state&);
void lua_bind_perlin_terrain(sol::state&);
void lua_bind_dial_type(sol::state&);
#if defined(SPACE_ENABLE_WALLET_CORE)
void lua_bind_wallet_core(sol::state&);
#endif
void lua_bind_libtorrent(sol::state&);

LuaRuntime::LuaRuntime() = default;

void LuaRuntime::init()
{
    install_fatal_traceback();
    lua.open_libraries(sol::lib::base, sol::lib::package, sol::lib::table,
                       sol::lib::math, sol::lib::string, sol::lib::debug,
                       sol::lib::io, sol::lib::os, sol::lib::utf8);
    lua.require("lsqlite3", luaopen_lsqlite3);
    http = std::make_unique<HttpClient>();
    install_base_bindings();
    configure_package_paths();
    lua["package"]["preload"]["runtime"] = [this](sol::this_state ts) -> sol::object {
        sol::state_view lua_view(ts);
        sol::table runtime_table = lua_view.create_table();
        runtime_table["assets-path"] = assets_path_value;
        runtime_table["fennel-path"] = fennel_path_value;
        return sol::make_object(lua_view, runtime_table);
    };

}

void LuaRuntime::install_fennel(bool correlate)
{
    lua["__SPACE_FENNEL_PATH"] = fennel_path_value;
    lua["__SPACE_FENNEL_CORRELATE"] = correlate;
    lua.script(
        "app = app or {}\n"
        "local fennel = require(\"fennel\")\n"
        "fennel.path = __SPACE_FENNEL_PATH .. \";\" .. fennel.path\n"
        "fennel[\"macro-path\"] = __SPACE_FENNEL_PATH .. \";\" .. fennel[\"macro-path\"]\n"
        "fennel.install({ correlate = __SPACE_FENNEL_CORRELATE })\n"
        "__SPACE_FENNEL_PATH = nil\n"
        "__SPACE_FENNEL_CORRELATE = nil\n");
}

void LuaRuntime::require_module(const std::string& name)
{
    require_module_object(name);
}

sol::object LuaRuntime::require_module_object(const std::string& name)
{
    sol::function require = lua["require"];
    sol::protected_function protected_require = require;
    sol::protected_function_result result = protected_require(name);
    throw_if_invalid(std::move(result));
    return result.get<sol::object>();
}

sol::function LuaRuntime::require_table_function(const std::string& module_name, const std::string& function_name)
{
    sol::object module_obj = require_module_object(module_name);
    if (!module_obj.is<sol::table>()) {
        throw sol::error("module " + module_name + " did not return a table for :" + function_name);
    }

    sol::table module_table = module_obj.as<sol::table>();
    sol::object function_obj = module_table[function_name];
    if (!function_obj.is<sol::function>()) {
        throw sol::error("module " + module_name + " missing function " + function_name);
    }

    return function_obj.as<sol::function>();
}

void LuaRuntime::execute_module_function(const std::string& module_name, const std::string& function_name)
{
    call_function(require_table_function(module_name, function_name));
}

void LuaRuntime::execute_fennel(const std::string& source)
{
    call_function(require_table_function("fennel", "eval"), source);
}

void LuaRuntime::execute_fennel_file(const std::string& path)
{
    call_function(require_table_function("fennel", "dofile"), path);
}

void LuaRuntime::execute_lua_file(const std::string& path)
{
    sol::protected_function_result result = lua.safe_script_file(path);
    throw_if_invalid(std::move(result));
}

void LuaRuntime::throw_if_invalid(sol::protected_function_result&& result)
{
    if (!result.valid()) {
        sol::error err = result;
        throw sol::error(err.what());
    }
}

void LuaRuntime::call_function(const sol::function& function)
{
    sol::protected_function protected_function = function;
    sol::protected_function_result result = protected_function();
    throw_if_invalid(std::move(result));
}

void LuaRuntime::call_function(const sol::function& function, const std::string& argument)
{
    sol::protected_function protected_function = function;
    sol::protected_function_result result = protected_function(argument);
    throw_if_invalid(std::move(result));
}

void LuaRuntime::install_fatal_traceback()
{
    lua["__FENNEL_FATAL_TRACEBACK"] =
        [](sol::object err, sol::this_state ts) -> sol::object {

            sol::state_view lua(ts);

            std::string errstr;
            try {
                errstr = err.as<std::string>();
            } catch (...) {
                errstr = "Lua fatal error (non-string error object)";
            }

            sol::function tb = lua["debug"]["traceback"];
            std::string traced = tb(errstr, 2);

            log_write_file_only("lua", Error, traced);
            std::cerr << traced << "\n";

            std::abort();

            return sol::make_object(lua, traced);
        };
}

void LuaRuntime::install_base_bindings()
{
    {
        sol::table callbacks_space = lua.create_table();
        lua_bind_callbacks(lua, callbacks_space);
    }
    lua_bind_opengl(lua);
    lua_bind_image_io(lua);
    lua_bind_json(lua);
    lua_bind_toml(lua);
    lua_bind_shaders(lua);
    lua_bind_textures(lua);
    lua_bind_glm(lua);
    lua_bind_vector_buffer(lua);
    lua_bind_graph_edge_batch(lua);
    lua_bind_tree_sitter(lua);
    lua_bind_msdf_atlas_gen(lua);
    lua_bind_cgltf(lua);
    lua_bind_fs(lua);
    lua_bind_appdirs(lua);
    lua_bind_random(lua);
    lua_bind_physics(lua);
    lua_bind_force_layout(lua);
    lua_bind_colors(lua);
    lua_bind_audio(lua);
    lua_bind_file_watch(lua);
    lua_bind_audio_input(lua);
    lua_bind_aubio(lua);
#if defined(SPACE_HAS_VTERM)
    lua_bind_terminal(lua);
#endif
    lua_bind_input_state(lua);
    lua_bind_zmq(lua);
    lua_bind_matrix(lua);
    lua_bind_realtime(lua);
    lua_bind_logging(lua);
    lua_bind_error_reporting(lua);
    lua_bind_uuid(lua);
    lua_bind_shell(lua);
    lua_bind_process(lua);
    lua_bind_http(lua, *http);
    lua_bind_http_server(lua);
    lua_bind_gccjit(lua);
    lua_bind_sysinfo(lua);
    lua_bind_perlin_terrain(lua);
    lua_bind_dial_type(lua);
    lua_bind_video(lua);
    lua_bind_xapian(lua);
#if defined(SPACE_ENABLE_WALLET_CORE)
    lua_bind_wallet_core(lua);
#else
    {
        sol::table package = lua["package"];
        sol::table preload = package["preload"];
        preload.set_function("wallet-core", [](sol::this_state state) {
            sol::state_view lua_state(state);
            sol::table wallet_core = lua_state.create_table();
            wallet_core["available"] = false;
            wallet_core["missing-reason"] = "wallet-core built without support";
            sol::table mt = lua_state.create_table();
            mt["__index"] = [](sol::this_state, sol::object key) -> sol::object {
                std::string key_name = "<non-string>";
                if (key.is<std::string>()) {
                    key_name = key.as<std::string>();
                }
                throw sol::error("wallet-core unavailable (built without wallet-core support): " + key_name);
                return sol::nil;
            };
            wallet_core[sol::metatable_key] = mt;
            return wallet_core;
        });
    }
#endif
    lua_bind_libtorrent(lua);
    lua_bind_engine(lua);
    lua_bind_ray_box(lua);
    lua_bind_tray(lua);
    lua_bind_notify(lua);
    lua_bind_webbrowser(lua);
}

void LuaRuntime::configure_package_paths()
{
    assets_path_value = AssetManager::getAssetPath("");
    std::string lua_path = AssetManager::getAssetPath("lua");
    std::string package_path = lua_path + "/?.lua";
    fennel_path_value = make_fennel_asset_search_path(lua_path);
    lua["package"]["path"] = lua["package"]["path"].get<std::string>() + ";" + package_path;
}

LuaRuntime::~LuaRuntime()
{
    lua_http_server_shutdown_all();
    if (http) {
        http->shutdown();
        lua_http_drop(lua);
    }
}

HttpClient& LuaRuntime::http_client()
{
    return *http;
}
