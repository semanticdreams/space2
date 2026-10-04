#pragma once

#include <memory>
#include <string>

#ifndef SOL_ALL_SAFETIES_ON
#define SOL_ALL_SAFETIES_ON 1
#endif
#include <sol/sol.hpp>

class HttpClient;
namespace space::ssh { class Service; }

class LuaRuntime {
public:
    LuaRuntime();
    ~LuaRuntime();
    void init();
    void install_fennel(bool correlate);
    void require_module(const std::string& name);
    void execute_module_function(const std::string& module_name, const std::string& function_name);
    void execute_fennel(const std::string& source);
    void execute_fennel_file(const std::string& path);
    void execute_lua_file(const std::string& path);

    sol::state& state() { return lua; }
    const std::string& assets_path() const { return assets_path_value; }
    const std::string& fennel_path() const { return fennel_path_value; }
    HttpClient& http_client();

private:
    sol::object require_module_object(const std::string& name);
    sol::function require_table_function(const std::string& module_name, const std::string& function_name);
    void throw_if_invalid(sol::protected_function_result&& result);
    void call_function(const sol::function& function);
    void call_function(const sol::function& function, const std::string& argument);
    void install_fatal_traceback();
    void install_base_bindings();
    void configure_package_paths();

    sol::state lua;
    std::string assets_path_value;
    std::string fennel_path_value;
    std::unique_ptr<HttpClient> http;
    std::shared_ptr<space::ssh::Service> ssh;
};
