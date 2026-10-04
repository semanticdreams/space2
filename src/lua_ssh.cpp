#include "lua_ssh.h"

#include "lua_callbacks.h"

#include <algorithm>
#include <cstdint>
#include <deque>
#include <map>
#include <set>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace
{
using namespace space::ssh;

struct SshLuaState
{
    std::shared_ptr<Service> service;
    std::deque<Event> buffered_events;
    std::unordered_map<OperationId, uint64_t> callback_by_operation;
};

std::unordered_map<lua_State*, SshLuaState> states;

bool terminal_event(EventKind kind)
{
    return kind == EventKind::OperationSuccess ||
        kind == EventKind::OperationError ||
        kind == EventKind::OperationTimeout ||
        kind == EventKind::OperationCancelled;
}

SshLuaState& state_for(sol::this_state this_state)
{
    auto it = states.find(this_state.lua_state());
    if (it == states.end() || !it->second.service)
    {
        throw sol::error("ssh module is not bound");
    }
    return it->second;
}

SshLuaState& state_for(sol::state& lua)
{
    auto it = states.find(lua.lua_state());
    if (it == states.end() || !it->second.service)
    {
        throw sol::error("ssh module is not bound");
    }
    return it->second;
}

std::string require_string(const sol::table& table, const std::string& key, bool required = true)
{
    sol::object value = table[key];
    if (!value.valid() || value == sol::lua_nil)
    {
        if (required)
        {
            throw sol::error("ssh option " + key + " is required");
        }
        return {};
    }
    if (!value.is<std::string>())
    {
        throw sol::error("ssh option " + key + " must be a string");
    }
    std::string text = value.as<std::string>();
    if (required && text.empty())
    {
        throw sol::error("ssh option " + key + " must be non-empty");
    }
    return text;
}

uint64_t optional_positive_u64(const sol::table& table, const std::string& key, uint64_t fallback = 0)
{
    sol::object value = table[key];
    if (!value.valid() || value == sol::lua_nil)
    {
        return fallback;
    }
    if (!value.is<double>() && !value.is<int>() && !value.is<uint64_t>())
    {
        throw sol::error("ssh option " + key + " must be a positive number");
    }
    double number = value.as<double>();
    if (number <= 0.0 || number != static_cast<double>(static_cast<uint64_t>(number)))
    {
        throw sol::error("ssh option " + key + " must be a positive integer");
    }
    return static_cast<uint64_t>(number);
}

uint16_t optional_port(const sol::table& table, const std::string& key, uint16_t fallback)
{
    uint64_t port = optional_positive_u64(table, key, fallback);
    if (port > 65535)
    {
        throw sol::error("ssh option " + key + " must be between 1 and 65535");
    }
    return static_cast<uint16_t>(port);
}

void reject_unknown_keys(const sol::table& table, const std::set<std::string>& allowed, const std::string& context)
{
    for (const auto& pair : table)
    {
        const sol::object& key = pair.first;
        if (!key.is<std::string>())
        {
            continue;
        }
        std::string key_name = key.as<std::string>();
        if (allowed.find(key_name) == allowed.end())
        {
            throw sol::error("unknown ssh option " + context + key_name);
        }
    }
}

KnownHostPolicy parse_policy(const std::string& value)
{
    if (value == "reject") return KnownHostPolicy::Reject;
    if (value == "ask") return KnownHostPolicy::Ask;
    if (value == "accept-once") return KnownHostPolicy::AcceptOnce;
    if (value == "accept-and-store") return KnownHostPolicy::AcceptAndStore;
    throw sol::error("ssh option known-host-policy has invalid value");
}

KnownHostDecision parse_decision(const std::string& value)
{
    if (value == "reject") return KnownHostDecision::Reject;
    if (value == "accept-once") return KnownHostDecision::AcceptOnce;
    if (value == "accept-and-store") return KnownHostDecision::AcceptAndStore;
    throw sol::error("ssh known host decision has invalid value");
}

AuthMethodType parse_auth_type(const std::string& value)
{
    if (value == "agent") return AuthMethodType::Agent;
    if (value == "private-key") return AuthMethodType::PrivateKey;
    if (value == "password") return AuthMethodType::Password;
    throw sol::error("ssh option auth-methods.type has invalid value");
}

std::vector<AuthMethod> parse_auth_methods(const sol::table& auth_table)
{
    std::set<std::size_t> indexes;
    std::size_t max_index = 0;
    for (const auto& pair : auth_table)
    {
        const sol::object& key = pair.first;
        const sol::object& value = pair.second;
        if (!key.is<double>() && !key.is<int>() && !key.is<uint64_t>())
        {
            throw sol::error("ssh option auth-methods must be an array");
        }
        double numeric_key = key.as<double>();
        std::size_t index = static_cast<std::size_t>(numeric_key);
        if (numeric_key <= 0.0 || numeric_key != static_cast<double>(index))
        {
            throw sol::error("ssh option auth-methods must use positive integer indexes");
        }
        if (!value.is<sol::table>())
        {
            throw sol::error("ssh option auth-methods item must be a table");
        }
        indexes.insert(index);
        max_index = std::max(max_index, index);
    }

    if (indexes.size() != max_index)
    {
        throw sol::error("ssh option auth-methods must be contiguous");
    }

    std::vector<AuthMethod> methods;
    methods.reserve(indexes.size());
    for (std::size_t i = 1; i <= max_index; ++i)
    {
        sol::table item = auth_table[static_cast<int>(i)];
        reject_unknown_keys(item, { "type", "key-path", "passphrase", "password" }, "auth-methods.");
        AuthMethod method;
        method.type = parse_auth_type(require_string(item, "type"));
        method.key_path = require_string(item, "key-path", false);
        method.passphrase = require_string(item, "passphrase", false);
        method.password = require_string(item, "password", false);
        methods.push_back(std::move(method));
    }
    return methods;
}

ConnectOptions parse_connect_options(const sol::table& opts)
{
    reject_unknown_keys(opts, { "target", "auth-methods", "known-host-policy", "known-hosts-path", "timeout-ms" }, "connect.");

    sol::object target_obj = opts["target"];
    if (!target_obj.is<sol::table>())
    {
        throw sol::error("ssh option target.host is required");
    }
    sol::table target_table = target_obj.as<sol::table>();
    reject_unknown_keys(target_table, { "host", "port", "username" }, "target.");

    ConnectOptions result;
    result.target.host = require_string(target_table, "host");
    result.target.port = optional_port(target_table, "port", 22);
    result.target.username = require_string(target_table, "username", false);
    result.timeout_ms = optional_positive_u64(opts, "timeout-ms", 0);
    result.known_hosts_path = require_string(opts, "known-hosts-path", false);

    sol::object policy_obj = opts["known-host-policy"];
    if (policy_obj.valid() && policy_obj != sol::lua_nil)
    {
        if (!policy_obj.is<std::string>())
        {
            throw sol::error("ssh option known-host-policy must be a string");
        }
        result.known_host_policy = parse_policy(policy_obj.as<std::string>());
    }

    sol::object auth_obj = opts["auth-methods"];
    if (auth_obj.valid() && auth_obj != sol::lua_nil)
    {
        if (!auth_obj.is<sol::table>())
        {
            throw sol::error("ssh option auth-methods must be a table");
        }
        sol::table auth_table = auth_obj.as<sol::table>();
        result.auth_methods = parse_auth_methods(auth_table);
    }

    return result;
}

ExecOptions parse_exec_options(const sol::table& opts)
{
    reject_unknown_keys(opts, { "command", "env", "timeout-ms" }, "exec.");
    ExecOptions result;
    result.command = require_string(opts, "command");
    result.timeout_ms = optional_positive_u64(opts, "timeout-ms", 0);
    sol::object env_obj = opts["env"];
    if (env_obj.valid() && env_obj != sol::lua_nil)
    {
        if (!env_obj.is<sol::table>())
        {
            throw sol::error("ssh option env must be a table");
        }
        for (const auto& pair : env_obj.as<sol::table>())
        {
            if (!pair.first.is<std::string>() || !pair.second.is<std::string>())
            {
                throw sol::error("ssh option env keys and values must be strings");
            }
            result.env[pair.first.as<std::string>()] = pair.second.as<std::string>();
        }
    }
    return result;
}

SftpTransferOptions parse_sftp_options(const sol::table& opts)
{
    reject_unknown_keys(opts, { "local-path", "remote-path", "timeout-ms" }, "sftp.");
    SftpTransferOptions result;
    result.local_path = require_string(opts, "local-path");
    result.remote_path = require_string(opts, "remote-path");
    result.timeout_ms = optional_positive_u64(opts, "timeout-ms", 0);
    return result;
}

ShellOptions parse_shell_options(const sol::table& opts)
{
    reject_unknown_keys(opts, { "request-pty", "term", "cols", "rows", "timeout-ms" }, "shell.");
    ShellOptions result;
    result.request_pty = opts.get_or("request-pty", false);
    result.term = require_string(opts, "term", false);
    result.cols = static_cast<uint32_t>(optional_positive_u64(opts, "cols", result.cols));
    result.rows = static_cast<uint32_t>(optional_positive_u64(opts, "rows", result.rows));
    result.timeout_ms = optional_positive_u64(opts, "timeout-ms", 0);
    return result;
}

TunnelOptions parse_tunnel_options(const sol::table& opts)
{
    reject_unknown_keys(opts, { "local-host", "local-port", "remote-host", "remote-port", "timeout-ms" }, "tunnel.");
    TunnelOptions result;
    result.local_host = require_string(opts, "local-host", false);
    result.local_port = optional_port(opts, "local-port", 0);
    result.remote_host = require_string(opts, "remote-host", false);
    result.remote_port = optional_port(opts, "remote-port", 0);
    result.timeout_ms = optional_positive_u64(opts, "timeout-ms", 0);
    return result;
}

sol::table event_to_lua(sol::state_view lua, const Event& event)
{
    sol::table table = lua.create_table();
    table["kind"] = event_kind_to_string(event.kind);
    if (event.operation_id != 0) table["operation-id"] = event.operation_id;
    if (event.session_id != 0) table["session-id"] = event.session_id;
    if (event.channel_id != 0) table["channel-id"] = event.channel_id;
    if (event.tunnel_id != 0) table["tunnel-id"] = event.tunnel_id;
    sol::table fields = lua.create_table();
    for (const auto& [key, value] : redact_secret_fields(event.fields))
    {
        fields[key] = value;
    }
    table["fields"] = fields;
    table["error-code"] = error_code_to_string(event.error_code);
    table["message"] = event.message;
    return table;
}

void handle_polled_event(sol::state_view lua, SshLuaState& state, Event event)
{
    auto callback_it = state.callback_by_operation.find(event.operation_id);
    if (callback_it == state.callback_by_operation.end())
    {
        state.buffered_events.push_back(std::move(event));
        return;
    }

    const uint64_t callback_id = callback_it->second;
    const bool terminal = terminal_event(event.kind);
    lua_callbacks_enqueue(callback_id, [event](sol::state_view callback_lua) {
        return sol::make_object(callback_lua, event_to_lua(callback_lua, event));
    });
    lua_callbacks_dispatch_ids(lua, { callback_id }, 1);
    if (terminal)
    {
        state.callback_by_operation.erase(callback_it);
        lua_callbacks_unregister(callback_id);
    }
}

OperationId remember_callback(SshLuaState& state, OperationId operation_id, sol::optional<sol::function> callback)
{
    if (callback)
    {
        state.callback_by_operation[operation_id] = lua_callbacks_register(callback.value());
    }
    return operation_id;
}

std::size_t max_results_from(sol::optional<uint64_t> max_results)
{
    return static_cast<std::size_t>(max_results.value_or(0));
}

sol::table poll_events(sol::this_state this_state, sol::optional<uint64_t> max_results)
{
    sol::state_view lua(this_state);
    SshLuaState& state = state_for(this_state);
    const std::size_t limit = max_results_from(max_results);
    sol::table result = lua.create_table();
    int index = 1;

    while (!state.buffered_events.empty() && (limit == 0 || static_cast<std::size_t>(index - 1) < limit))
    {
        result[index++] = event_to_lua(lua, state.buffered_events.front());
        state.buffered_events.pop_front();
    }

    const std::size_t remaining = limit == 0 ? 0 : limit - static_cast<std::size_t>(index - 1);
    std::vector<Event> events = state.service->poll(remaining);
    for (Event& event : events)
    {
        if (limit != 0 && static_cast<std::size_t>(index - 1) >= limit)
        {
            state.buffered_events.push_back(std::move(event));
            continue;
        }
        result[index++] = event_to_lua(lua, event);
    }
    return result;
}

} // namespace

void lua_bind_ssh(sol::state& lua, std::shared_ptr<Service> service)
{
    if (!service)
    {
        throw sol::error("ssh service is required");
    }

    states[lua.lua_state()].service = std::move(service);
    sol::table package = lua["package"];
    sol::table preload = package["preload"];
    preload.set_function("ssh", [](sol::this_state this_state) {
        sol::state_view lua(this_state);
        sol::table module = lua.create_table();

        module.set_function("connect", [](sol::this_state ts, sol::table opts, sol::optional<sol::function> callback) {
            SshLuaState& state = state_for(ts);
            return remember_callback(state, state.service->connect(parse_connect_options(opts)), callback);
        });
        module.set_function("resolve-known-host", [](sol::this_state ts, uint64_t operation_id, const std::string& decision) {
            return state_for(ts).service->resolve_known_host(operation_id, parse_decision(decision));
        });
        module.set_function("close-session", [](sol::this_state ts, uint64_t session_id) {
            return state_for(ts).service->close_session(session_id);
        });
        module.set_function("exec", [](sol::this_state ts, uint64_t session_id, sol::table opts, sol::optional<sol::function> callback) {
            SshLuaState& state = state_for(ts);
            return remember_callback(state, state.service->exec(session_id, parse_exec_options(opts)), callback);
        });
        module.set_function("sftp-upload", [](sol::this_state ts, uint64_t session_id, sol::table opts, sol::optional<sol::function> callback) {
            SshLuaState& state = state_for(ts);
            return remember_callback(state, state.service->sftp_upload(session_id, parse_sftp_options(opts)), callback);
        });
        module.set_function("sftp-download", [](sol::this_state ts, uint64_t session_id, sol::table opts, sol::optional<sol::function> callback) {
            SshLuaState& state = state_for(ts);
            return remember_callback(state, state.service->sftp_download(session_id, parse_sftp_options(opts)), callback);
        });
        module.set_function("open-shell", [](sol::this_state ts, uint64_t session_id, sol::optional<sol::table> opts, sol::optional<sol::function> callback) {
            SshLuaState& state = state_for(ts);
            sol::state_view lua(ts);
            ShellOptions options = opts ? parse_shell_options(opts.value()) : ShellOptions{};
            return remember_callback(state, state.service->open_shell(session_id, options), callback);
        });
        module.set_function("channel-write", [](sol::this_state ts, uint64_t channel_id, const std::string& data) {
            return state_for(ts).service->channel_write(channel_id, data);
        });
        module.set_function("channel-resize", [](sol::this_state ts, uint64_t channel_id, uint32_t cols, uint32_t rows) {
            return state_for(ts).service->channel_resize(channel_id, cols, rows);
        });
        module.set_function("channel-close", [](sol::this_state ts, uint64_t channel_id) {
            return state_for(ts).service->channel_close(channel_id);
        });
        module.set_function("open-local-tunnel", [](sol::this_state ts, uint64_t session_id, sol::table opts, sol::optional<sol::function> callback) {
            SshLuaState& state = state_for(ts);
            return remember_callback(state, state.service->open_local_tunnel(session_id, parse_tunnel_options(opts)), callback);
        });
        module.set_function("open-remote-tunnel", [](sol::this_state ts, uint64_t session_id, sol::table opts, sol::optional<sol::function> callback) {
            SshLuaState& state = state_for(ts);
            return remember_callback(state, state.service->open_remote_tunnel(session_id, parse_tunnel_options(opts)), callback);
        });
        module.set_function("close-tunnel", [](sol::this_state ts, uint64_t tunnel_id) {
            return state_for(ts).service->close_tunnel(tunnel_id);
        });
        module.set_function("cancel", [](sol::this_state ts, uint64_t operation_id) {
            return state_for(ts).service->cancel(operation_id);
        });
        module.set_function("poll", poll_events);

        return module;
    });
}

void lua_ssh_dispatch(sol::state& lua)
{
    auto it = states.find(lua.lua_state());
    if (it == states.end() || !it->second.service)
    {
        return;
    }
    SshLuaState& state = it->second;
    std::vector<Event> events = state.service->poll(0);
    sol::state_view lua_view(lua);
    for (Event& event : events)
    {
        handle_polled_event(lua_view, state, std::move(event));
    }
}

void lua_ssh_drop(sol::state& lua)
{
    auto it = states.find(lua.lua_state());
    if (it == states.end())
    {
        return;
    }
    std::vector<uint64_t> callback_ids;
    callback_ids.reserve(it->second.callback_by_operation.size());
    for (const auto& [operation_id, callback_id] : it->second.callback_by_operation)
    {
        (void)operation_id;
        callback_ids.push_back(callback_id);
    }
    for (uint64_t callback_id : callback_ids)
    {
        lua_callbacks_unregister(callback_id);
    }
    if (it->second.service)
    {
        it->second.service->shutdown();
    }
    states.erase(it);
}
