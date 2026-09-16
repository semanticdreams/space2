#include <atomic>
#include <chrono>
#include <iostream>
#include <mutex>
#include <optional>
#include <queue>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

#include "lua_callbacks.h"
#include "error_reporting.h"
#include "lua_http.h"
#include "lua_http_server.h"
#include "lua_jobs.h"
#include "lua_process.h"

namespace {

struct Pending {
    uint64_t id { 0 };
    std::function<sol::object(sol::state_view)> builder;
};

std::atomic<uint64_t> next_id { 1 };
std::mutex registry_mutex;
std::unordered_map<uint64_t, sol::protected_function> registry;
std::unordered_set<uint64_t> deferred_unregister_ids;
std::unordered_set<uint64_t> retired_ids;

std::mutex queue_mutex;
std::vector<Pending> pending_queue;
thread_local std::size_t dispatch_depth = 0;

std::vector<Pending> take_pending_callbacks(const std::unordered_set<uint64_t>* allowed_ids, std::size_t max_results)
{
    std::vector<Pending> to_process;
    std::lock_guard<std::mutex> lock(queue_mutex);
    if (pending_queue.empty()) {
        return to_process;
    }

    if (!allowed_ids && (max_results == 0 || max_results >= pending_queue.size())) {
        to_process.swap(pending_queue);
        return to_process;
    }

    std::vector<Pending> remaining;
    remaining.reserve(pending_queue.size());
    if (max_results > 0) {
        to_process.reserve(max_results);
    }

    for (auto& item : pending_queue) {
        const bool allowed = !allowed_ids || allowed_ids->find(item.id) != allowed_ids->end();
        const bool has_capacity = max_results == 0 || to_process.size() < max_results;
        if (allowed && has_capacity) {
            to_process.push_back(std::move(item));
        } else {
            remaining.push_back(std::move(item));
        }
    }

    pending_queue.swap(remaining);
    return to_process;
}

std::optional<uint64_t> parse_optional_u64(const sol::object& value)
{
    if (value.is<uint64_t>()) {
        return value.as<uint64_t>();
    }
    if (value.is<int>()) {
        int asInt = value.as<int>();
        if (asInt < 0) {
            throw sol::error("callbacks.run-loop value must be non-negative");
        }
        return static_cast<uint64_t>(asInt);
    }
    if (value.is<double>()) {
        double asDouble = value.as<double>();
        if (asDouble < 0.0) {
            throw sol::error("callbacks.run-loop value must be non-negative");
        }
        return static_cast<uint64_t>(asDouble);
    }
    return std::nullopt;
}

bool call_until(const sol::function& fn)
{
    sol::protected_function pf = fn;
    sol::protected_function_result result = pf();
    if (!result.valid()) {
        sol::error err = result;
        throw sol::error(err.what());
    }
    sol::object value = result.get<sol::object>();
    if (value.is<bool>()) {
        return value.as<bool>();
    }
    return value.valid() && value != sol::lua_nil;
}

void capture_callback_error(uint64_t id, const sol::error& error)
{
    error_reporting::capture_exception(
        "LuaCallbackError",
        error.what(),
        error.what(),
        {{"callback_id", std::to_string(id)}});
}

void flush_deferred_unregistrations()
{
    if (dispatch_depth != 0) {
        return;
    }

    std::unordered_set<uint64_t> ids;
    {
        std::lock_guard<std::mutex> lock(registry_mutex);
        if (deferred_unregister_ids.empty()) {
            return;
        }
        ids.swap(deferred_unregister_ids);
        for (uint64_t id : ids) {
            registry.erase(id);
            retired_ids.erase(id);
        }
    }
}

struct DispatchScope {
    DispatchScope()
    {
        ++dispatch_depth;
    }

    ~DispatchScope()
    {
        if (dispatch_depth > 0) {
            --dispatch_depth;
        }
        flush_deferred_unregistrations();
    }
};

} // namespace

void lua_bind_callbacks(sol::state& lua, sol::table& lua_space)
{
    sol::table package = lua["package"];
    sol::table loaded = package["loaded"];
    sol::object loaded_cb = loaded["callbacks"];
    sol::table cb;
    if (loaded_cb.is<sol::table>()) {
        cb = loaded_cb.as<sol::table>();
    } else {
        cb = lua.create_table();
        loaded["callbacks"] = cb;
    }

    cb.set_function("register", [](sol::function fn) {
        return lua_callbacks_register(std::move(fn));
    });
    cb.set_function("unregister", [](uint64_t id) {
        return lua_callbacks_unregister(id);
    });
    cb.set_function("enqueue", [](uint64_t id, sol::object payload) {
        lua_callbacks_enqueue(id, [payload](sol::state_view lua) {
            return sol::make_object(lua, payload);
        });
    });
    cb.set_function("dispatch", [&lua](sol::optional<uint64_t> max_results) {
        lua_callbacks_dispatch(lua, max_results.value_or(0));
    });
    cb.set_function("run-loop", [&lua](sol::optional<sol::table> opts) {
        bool poll_jobs = true;
        bool poll_http = true;
        bool poll_process = false;
        uint64_t sleep_ms = 1;
        uint64_t timeout_ms = 0;
        sol::optional<sol::function> until;

        if (opts) {
            sol::optional<bool> pollJobs = opts->get<sol::optional<bool>>("poll-jobs");
            sol::optional<bool> pollHttp = opts->get<sol::optional<bool>>("poll-http");
            sol::optional<bool> pollProcess = opts->get<sol::optional<bool>>("poll-process");
            sol::optional<sol::function> untilFn = opts->get<sol::optional<sol::function>>("until");
            if (pollJobs) {
                poll_jobs = *pollJobs;
            }
            if (pollHttp) {
                poll_http = *pollHttp;
            }
            if (pollProcess) {
                poll_process = *pollProcess;
            }
            if (untilFn) {
                until = untilFn;
            }
            sol::object sleepObj = opts->get<sol::object>("sleep-ms");
            if (sleepObj.valid() && sleepObj != sol::lua_nil) {
                auto parsed = parse_optional_u64(sleepObj);
                if (parsed) {
                    sleep_ms = *parsed;
                } else {
                    throw sol::error("callbacks.run-loop sleep-ms must be a number");
                }
            }
            sol::object timeoutObj = opts->get<sol::object>("timeout-ms");
            if (timeoutObj.valid() && timeoutObj != sol::lua_nil) {
                auto parsed = parse_optional_u64(timeoutObj);
                if (parsed) {
                    timeout_ms = *parsed;
                } else {
                    throw sol::error("callbacks.run-loop timeout-ms must be a number");
                }
            }
        }

        auto start = std::chrono::steady_clock::now();
        while (true) {
            if (poll_jobs) {
                lua_jobs_dispatch_active(lua);
            }
            if (poll_http) {
                lua_http_dispatch(lua);
            }
            if (poll_process) {
                lua_process_dispatch(lua);
            }
            lua_http_server_dispatch(lua);
            lua_callbacks_dispatch(lua);

            if (until && call_until(until.value())) {
                return true;
            }

            if (timeout_ms > 0) {
                auto now = std::chrono::steady_clock::now();
                auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(now - start).count();
                if (elapsed >= static_cast<long long>(timeout_ms)) {
                    return false;
                }
            }

            if (sleep_ms > 0) {
                std::this_thread::sleep_for(std::chrono::milliseconds(sleep_ms));
            }
        }
    });

    lua_space["callbacks"] = cb;

    sol::table preload = package["preload"];
    preload.set_function("callbacks", [cb](sol::this_state state) mutable {
        (void)state;
        return cb;
    });
}

uint64_t lua_callbacks_register(sol::function fn)
{
    sol::protected_function pf = std::move(fn);
    uint64_t id = next_id.fetch_add(1);
    std::lock_guard<std::mutex> lock(registry_mutex);
    registry[id] = std::move(pf);
    return id;
}

bool lua_callbacks_unregister(uint64_t id)
{
    std::lock_guard<std::mutex> lock(registry_mutex);
    if (dispatch_depth > 0) {
        deferred_unregister_ids.insert(id);
        return registry.find(id) != registry.end();
    }
    retired_ids.erase(id);
    return registry.erase(id) > 0;
}

void lua_callbacks_enqueue(uint64_t id, std::function<sol::object(sol::state_view)> payload_builder)
{
    Pending p;
    p.id = id;
    p.builder = std::move(payload_builder);
    std::lock_guard<std::mutex> lock(queue_mutex);
    pending_queue.push_back(std::move(p));
}

void lua_callbacks_dispatch(sol::state_view lua, std::size_t max_results)
{
    std::vector<Pending> to_process = take_pending_callbacks(nullptr, max_results);
    if (to_process.empty()) {
        return;
    }

    DispatchScope dispatch_scope;
    for (auto& item : to_process) {
        sol::protected_function callback;
        {
            std::lock_guard<std::mutex> lock(registry_mutex);
            if (retired_ids.find(item.id) != retired_ids.end()) {
                continue;
            }
            auto it = registry.find(item.id);
            if (it != registry.end()) {
                callback = it->second;
            }
        }
        if (!callback.valid()) {
            continue;
        }
        sol::object payload = item.builder ? item.builder(lua) : sol::lua_nil;
        sol::protected_function_result result = callback(payload);
        if (!result.valid()) {
            sol::error err = result;
            capture_callback_error(item.id, err);
            std::cerr << "[callbacks] invocation failed for id " << item.id << ": " << err.what() << "\n";
        }
    }
}

std::size_t lua_callbacks_dispatch_ids(sol::state_view lua, const std::vector<uint64_t>& ids, std::size_t max_results)
{
    if (ids.empty()) {
        return 0;
    }

    std::unordered_set<uint64_t> allowed_ids(ids.begin(), ids.end());
    std::vector<Pending> to_process = take_pending_callbacks(&allowed_ids, max_results);
    if (to_process.empty()) {
        return 0;
    }

    DispatchScope dispatch_scope;
    for (auto& item : to_process) {
        sol::protected_function callback;
        {
            std::lock_guard<std::mutex> lock(registry_mutex);
            if (retired_ids.find(item.id) != retired_ids.end()) {
                continue;
            }
            auto it = registry.find(item.id);
            if (it != registry.end()) {
                callback = it->second;
            }
        }
        if (!callback.valid()) {
            continue;
        }
        sol::object payload = item.builder ? item.builder(lua) : sol::lua_nil;
        sol::protected_function_result result = callback(payload);
        if (!result.valid()) {
            sol::error err = result;
            capture_callback_error(item.id, err);
            std::cerr << "[callbacks] invocation failed for id " << item.id << ": " << err.what() << "\n";
        }
    }

    return to_process.size();
}

void lua_callbacks_retire_ids(const std::vector<uint64_t>& ids)
{
    if (ids.empty()) {
        return;
    }

    {
        std::lock_guard<std::mutex> lock(registry_mutex);
        for (uint64_t id : ids) {
            retired_ids.insert(id);
        }
    }
    lua_callbacks_discard_ids(ids);
}

void lua_callbacks_discard_ids(const std::vector<uint64_t>& ids)
{
    if (ids.empty()) {
        return;
    }

    std::unordered_set<uint64_t> blocked_ids(ids.begin(), ids.end());
    std::lock_guard<std::mutex> lock(queue_mutex);
    if (pending_queue.empty()) {
        return;
    }

    std::vector<Pending> remaining;
    remaining.reserve(pending_queue.size());
    for (auto& item : pending_queue) {
        if (blocked_ids.find(item.id) == blocked_ids.end()) {
            remaining.push_back(std::move(item));
        }
    }
    pending_queue.swap(remaining);
}

void lua_callbacks_shutdown()
{
    {
        std::lock_guard<std::mutex> lock(registry_mutex);
        registry.clear();
        deferred_unregister_ids.clear();
        retired_ids.clear();
    }
    {
        std::lock_guard<std::mutex> lock(queue_mutex);
        pending_queue.clear();
    }
}
