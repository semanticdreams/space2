#include "lua_ssh.h"
#include "ssh_backend.h"
#include "ssh_service.h"

#include <atomic>
#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <exception>
#include <functional>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_map>
#include <utility>
#include <vector>

#include <sol/sol.hpp>

namespace
{
using namespace space::ssh;

std::unordered_map<uint64_t, sol::protected_function> callback_registry;
std::vector<std::pair<uint64_t, std::function<sol::object(sol::state_view)>>> callback_queue;
uint64_t next_callback_id = 1;

class FakeBackend : public Backend
{
public:
    void connect(OperationContext& context, const ConnectOptions&) override
    {
        context.sink().emit(Event{ EventKind::OperationStarted,
                                    context.operation_id(),
                                    0,
                                    0,
                                    0,
                                    {{ "password", "secret" }, { "passphrase", "hidden" }, { "safe", "visible" }} });

        if (known_host_mode.load())
        {
            context.sink().emit(Event{ EventKind::KnownHostChallenge, context.operation_id() });
            return;
        }

        const SessionId session_id = context.sink().allocate_session();
        context.sink().emit(Event{ EventKind::Connected, context.operation_id(), session_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    void resolve_known_host(OperationContext& context, KnownHostDecision decision) override
    {
        last_decision.store(static_cast<int>(decision));
        const SessionId session_id = context.sink().allocate_session();
        context.sink().emit(Event{ EventKind::Connected, context.operation_id(), session_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    void close_session(OperationContext& context, SessionId) override
    {
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id() });
    }

    void exec(OperationContext& context, SessionId, const ExecOptions&) override
    {
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id() });
    }

    void sftp_upload(OperationContext& context, SessionId, const SftpTransferOptions&) override
    {
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id() });
    }

    void sftp_download(OperationContext& context, SessionId, const SftpTransferOptions&) override
    {
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id() });
    }

    void open_shell(OperationContext& context, SessionId, const ShellOptions&) override
    {
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id() });
    }

    void channel_write(OperationContext& context, ChannelId, const std::string&) override
    {
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id() });
    }

    void channel_resize(OperationContext& context, ChannelId, uint32_t, uint32_t) override
    {
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id() });
    }

    void channel_close(OperationContext& context, ChannelId) override
    {
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id() });
    }

    void open_local_tunnel(OperationContext& context, SessionId, const TunnelOptions&) override
    {
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id() });
    }

    void open_remote_tunnel(OperationContext& context, SessionId, const TunnelOptions&) override
    {
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id() });
    }

    void close_tunnel(OperationContext& context, TunnelId) override
    {
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id() });
    }

    std::atomic<bool> known_host_mode { false };
    std::atomic<int> last_decision { -1 };
};

void expect_true(bool value, const std::string& message)
{
    if (!value)
    {
        throw std::runtime_error(message);
    }
}

void wait_for_events()
{
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
}

} // namespace

uint64_t lua_callbacks_register(sol::function fn)
{
    const uint64_t id = next_callback_id++;
    callback_registry[id] = sol::protected_function(std::move(fn));
    return id;
}

bool lua_callbacks_unregister(uint64_t id)
{
    return callback_registry.erase(id) > 0;
}

void lua_callbacks_enqueue(uint64_t id, std::function<sol::object(sol::state_view)> payload_builder)
{
    callback_queue.emplace_back(id, std::move(payload_builder));
}

void lua_callbacks_dispatch(sol::state_view lua, std::size_t)
{
    auto queue = std::move(callback_queue);
    callback_queue.clear();
    for (auto& [id, builder] : queue)
    {
        auto it = callback_registry.find(id);
        if (it != callback_registry.end())
        {
            sol::protected_function_result result = it->second(builder(lua));
            if (!result.valid())
            {
                sol::error err = result;
                throw sol::error(err.what());
            }
        }
    }
}

std::size_t lua_callbacks_dispatch_ids(sol::state_view lua, const std::vector<uint64_t>& ids, std::size_t max_results)
{
    std::size_t dispatched = 0;
    std::vector<std::pair<uint64_t, std::function<sol::object(sol::state_view)>>> remaining;
    for (auto& item : callback_queue)
    {
        const bool allowed = std::find(ids.begin(), ids.end(), item.first) != ids.end();
        const bool capacity = max_results == 0 || dispatched < max_results;
        if (allowed && capacity)
        {
            auto it = callback_registry.find(item.first);
            if (it != callback_registry.end())
            {
                sol::protected_function_result result = it->second(item.second(lua));
                if (!result.valid())
                {
                    sol::error err = result;
                    throw sol::error(err.what());
                }
            }
            ++dispatched;
        }
        else
        {
            remaining.push_back(std::move(item));
        }
    }
    callback_queue.swap(remaining);
    return dispatched;
}

void lua_callbacks_shutdown()
{
    callback_registry.clear();
    callback_queue.clear();
}

int main()
{
    try
    {
        sol::state lua;
        lua.open_libraries(sol::lib::base, sol::lib::package, sol::lib::table, sol::lib::string, sol::lib::math);

        auto backend = std::make_unique<FakeBackend>();
        FakeBackend* backend_ptr = backend.get();
        auto service = std::make_shared<Service>(std::move(backend));
        lua_bind_ssh(lua, service);

        lua.script(R"(
            local ssh = require("ssh")
            assert(type(ssh) == "table")
            assert(ssh.available == true)
            assert(ssh["missing-reason"] == nil)

            local names = {
                "connect", "resolve-known-host", "close-session", "exec",
                "sftp-upload", "sftp-download", "open-shell", "channel-write",
                "channel-resize", "channel-close", "open-local-tunnel",
                "open-remote-tunnel", "close-tunnel", "cancel", "poll"
            }
            for _, name in ipairs(names) do
                assert(type(ssh[name]) == "function", name)
            end

            local ok, err = pcall(function() ssh.connect({}) end)
            assert(ok == false)
            assert(string.find(tostring(err), "target.host", 1, true))

            ok, err = pcall(function()
                ssh.connect({ target = { host = "h" }, authMethods = {} })
            end)
            assert(ok == false)
            assert(string.find(tostring(err), "authMethods", 1, true))

            ok, err = pcall(function()
                ssh.connect({ target = { host = "h" }, timeout_ms = 1 })
            end)
            assert(ok == false)
            assert(string.find(tostring(err), "timeout_ms", 1, true))

            local op = ssh.connect({
                target = { host = "h" },
                ["auth-methods"] = { { type = "password", password = "secret" } }
            })
            assert(type(op) == "number")

            ok, err = pcall(function()
                ssh.connect({
                    target = { host = "h" },
                    ["auth-methods"] = { named = { type = "agent" } }
                })
            end)
            assert(ok == false)
            assert(string.find(tostring(err), "auth-methods", 1, true))

            ok, err = pcall(function()
                local sparse = {}
                sparse[2] = { type = "agent" }
                ssh.connect({ target = { host = "h" }, ["auth-methods"] = sparse })
            end)
            assert(ok == false)
            assert(string.find(tostring(err), "auth-methods", 1, true))
        )");

        wait_for_events();
        lua.script(R"(
            local ssh = require("ssh")
            local events = ssh.poll()
            assert(type(events) == "table")
            assert(#events >= 1)
            local first = events[1]
            assert(first.kind ~= nil)
            assert(first["operation-id"] ~= nil)
            assert(first["session-id"] == nil or type(first["session-id"]) == "number")
            assert(first["channel-id"] == nil or type(first["channel-id"]) == "number")
            assert(first["tunnel-id"] == nil or type(first["tunnel-id"]) == "number")
            assert(type(first.fields) == "table")
            assert(first["error-code"] ~= nil)
            assert(first.message ~= nil)

            local function scan(value)
                if type(value) == "string" then
                    assert(not string.find(value, "secret", 1, true))
                    assert(not string.find(value, "hidden", 1, true))
                elseif type(value) == "table" then
                    for k, v in pairs(value) do
                        scan(k)
                        scan(v)
                    end
                end
            end
            scan(events)

            assert(ssh.cancel(999999) == false)
        )");

        lua.script(R"(
            local ssh = require("ssh")
            callback_event = nil
            callback_events = {}
            callback_op = ssh.connect({ target = { host = "h" } }, function(event)
                callback_event = event
                table.insert(callback_events, event)
            end)
        )");
        for (int i = 0; i < 50; ++i)
        {
            lua_ssh_dispatch(lua);
            sol::table events = lua["callback_events"];
            if (events.valid() && events.size() >= 3)
            {
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
        }
        expect_true(lua["callback_event"].valid() && lua["callback_event"] != sol::lua_nil,
                    "SSH callback did not receive a terminal event");
        lua.script(R"(
            assert(callback_event.kind == "operation-success", callback_event.kind)
        )");

        backend_ptr->known_host_mode.store(true);
        lua.script(R"(
            local ssh = require("ssh")
            known_host_callback_events = {}
            known_host_callback_op = ssh.connect({ target = { host = "h" } }, function(event)
                table.insert(known_host_callback_events, event)
            end)
        )");
        for (int i = 0; i < 50; ++i)
        {
            lua_ssh_dispatch(lua);
            sol::table events = lua["known_host_callback_events"];
            if (events.valid() && events.size() >= 2)
            {
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
        }
        lua.script(R"(
            local ssh = require("ssh")
            assert(#known_host_callback_events >= 2, #known_host_callback_events)
            assert(known_host_callback_events[1].kind == "operation-started", known_host_callback_events[1].kind)
            assert(known_host_callback_events[2].kind == "known-host-challenge", known_host_callback_events[2].kind)
            assert(ssh["resolve-known-host"](known_host_callback_op, "accept-once") == true)
        )");
        for (int i = 0; i < 50; ++i)
        {
            lua_ssh_dispatch(lua);
            sol::table events = lua["known_host_callback_events"];
            if (events.valid() && events.size() >= 4)
            {
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
        }
        lua.script(R"(
            assert(known_host_callback_events[#known_host_callback_events].kind == "operation-success",
                   known_host_callback_events[#known_host_callback_events].kind)
        )");

        lua.script(R"(
            local ssh = require("ssh")
            known_host_op = ssh.connect({ target = { host = "h" } })
        )");
        wait_for_events();
        lua.script(R"(
            local ssh = require("ssh")
            assert(ssh["resolve-known-host"](known_host_op, "accept-once") == true)
        )");
        wait_for_events();
        expect_true(backend_ptr->last_decision.load() == static_cast<int>(KnownHostDecision::AcceptOnce),
                    "accept-once did not map to KnownHostDecision::AcceptOnce");

        lua_ssh_drop(lua);
        service->shutdown();
        lua_callbacks_shutdown();

        sol::state unavailable_lua;
        unavailable_lua.open_libraries(sol::lib::base, sol::lib::package, sol::lib::table, sol::lib::string, sol::lib::math);
        auto unavailable_service = std::make_shared<Service>(make_unavailable_backend("libssh backend not available"));
        lua_bind_ssh(unavailable_lua, unavailable_service);
        unavailable_lua.script(R"(
            local ssh = require("ssh")
            assert(ssh.available == false)
            assert(ssh["missing-reason"] == "libssh backend not available")
        )");
        lua_ssh_drop(unavailable_lua);
        unavailable_service->shutdown();
        lua_callbacks_shutdown();
    }
    catch (const std::exception& ex)
    {
        std::cerr << "test_lua_ssh_binding failure: " << ex.what() << '\n';
        return EXIT_FAILURE;
    }

    return EXIT_SUCCESS;
}
