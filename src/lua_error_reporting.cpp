#include <sol/sol.hpp>

#include <string>
#include <utility>
#include <vector>

#include "error_reporting.h"

namespace {

std::string type_name(sol::type type)
{
    switch (type) {
    case sol::type::none: return "none";
    case sol::type::lua_nil: return "nil";
    case sol::type::string: return "string";
    case sol::type::number: return "number";
    case sol::type::thread: return "thread";
    case sol::type::boolean: return "boolean";
    case sol::type::function: return "function";
    case sol::type::userdata: return "userdata";
    case sol::type::lightuserdata: return "lightuserdata";
    case sol::type::table: return "table";
    case sol::type::poly: return "poly";
    }
    return "unknown";
}

[[noreturn]] void throw_type_error(const std::string& key, const std::string& expected, sol::type actual)
{
    throw sol::error("error-reporting option " + key + " must be " + expected + ", got " + type_name(actual));
}

std::string require_string(sol::table table, const std::string& key)
{
    sol::object value = table[key];
    if (!value.is<std::string>()) {
        throw_type_error(key, "string", value.get_type());
    }
    return value.as<std::string>();
}

std::string require_non_empty_string(sol::table table, const std::string& key)
{
    std::string value = require_string(table, key);
    if (value.empty()) {
        throw sol::error("error-reporting option " + key + " must be a non-empty string");
    }
    return value;
}

std::string optional_string(sol::table table, const std::string& key)
{
    sol::object value = table[key];
    if (value == sol::nil) {
        return "";
    }
    if (!value.is<std::string>()) {
        throw_type_error(key, "string", value.get_type());
    }
    return value.as<std::string>();
}

bool optional_bool(sol::table table, const std::string& key)
{
    sol::object value = table[key];
    if (value == sol::nil) {
        return false;
    }
    if (!value.is<bool>()) {
        throw_type_error(key, "boolean", value.get_type());
    }
    return value.as<bool>();
}

bool is_allowed_init_option(const std::string& key)
{
    return key == "dsn" || key == "environment" || key == "release" || key == "database-path"
        || key == "debug";
}

void validate_init_option_keys(sol::table table)
{
    for (const auto& item : table) {
        sol::object key_obj = item.first;
        if (!key_obj.is<std::string>()) {
            throw sol::error("error-reporting init option keys must be strings");
        }

        const std::string key = key_obj.as<std::string>();
        if (!is_allowed_init_option(key)) {
            throw sol::error("error-reporting unknown init option: " + key);
        }
    }
}

error_reporting::Level parse_level(const std::string& level)
{
    if (level == "fatal") {
        return error_reporting::Level::Fatal;
    }
    if (level == "error") {
        return error_reporting::Level::Error;
    }
    if (level == "warning" || level == "warn") {
        return error_reporting::Level::Warning;
    }
    if (level == "info") {
        return error_reporting::Level::Info;
    }
    if (level == "debug") {
        return error_reporting::Level::Debug;
    }
    throw sol::error("error-reporting invalid level: " + level);
}

error_reporting::InitOptions parse_init_options(sol::object options_obj)
{
    if (!options_obj.is<sol::table>()) {
        throw sol::error("error-reporting init options must be a table");
    }

    sol::table options_table = options_obj.as<sol::table>();
    validate_init_option_keys(options_table);

    error_reporting::InitOptions options;
    options.dsn = require_non_empty_string(options_table, "dsn");
    options.environment = optional_string(options_table, "environment");
    options.release = optional_string(options_table, "release");
    options.database_path = optional_string(options_table, "database-path");
    options.debug = optional_bool(options_table, "debug");
    return options;
}

std::vector<std::pair<std::string, std::string>> parse_tags(sol::object tags_obj)
{
    std::vector<std::pair<std::string, std::string>> tags;
    if (tags_obj == sol::nil) {
        return tags;
    }
    if (!tags_obj.is<sol::table>()) {
        throw sol::error("error-reporting capture-error tags must be a table");
    }

    sol::table tags_table = tags_obj.as<sol::table>();
    for (const auto& item : tags_table) {
        sol::object key_obj = item.first;
        sol::object value_obj = item.second;
        if (!key_obj.is<std::string>()) {
            throw sol::error("error-reporting capture-error tag keys must be strings");
        }
        if (!value_obj.is<std::string>()) {
            throw sol::error("error-reporting capture-error tag values must be strings");
        }
        tags.emplace_back(key_obj.as<std::string>(), value_obj.as<std::string>());
    }
    return tags;
}

bool capture_error(sol::object error_obj)
{
    if (!error_obj.is<sol::table>()) {
        throw sol::error("error-reporting capture-error payload must be a table");
    }

    sol::table error_table = error_obj.as<sol::table>();
    const std::string type = require_non_empty_string(error_table, "type");
    const std::string message = require_string(error_table, "message");
    const std::string stacktrace = optional_string(error_table, "stacktrace");
    std::vector<std::pair<std::string, std::string>> tags = parse_tags(error_table["tags"]);
    return error_reporting::capture_exception(type, message, stacktrace, tags);
}

} // namespace

void lua_bind_error_reporting(sol::state& lua)
{
    sol::table package = lua["package"];
    sol::table preload = package["preload"];

    preload.set_function("error-reporting", [](sol::this_state state) {
        sol::state_view lua_view(state);
        sol::table reporting_table = lua_view.create_table();

        reporting_table.set_function("init", [](sol::object options_obj) {
            error_reporting::InitOptions options = parse_init_options(options_obj);
            std::string error_message;
            if (!error_reporting::init(options, &error_message)) {
                throw sol::error("error-reporting init failed: " + error_message);
            }
            return true;
        });
        reporting_table.set_function("enabled?", &error_reporting::is_enabled);
        reporting_table.set_function("capture-message", [](const std::string& level,
                                                            const std::string& logger,
                                                            const std::string& message) {
            return error_reporting::capture_message(parse_level(level), logger, message);
        });
        reporting_table.set_function("capture-error", &capture_error);
        reporting_table.set_function("flush", &error_reporting::flush);
        reporting_table.set_function("shutdown", &error_reporting::shutdown);

        return reporting_table;
    });
}
