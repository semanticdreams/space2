#include "ssh_backend.h"
#include "ssh_service.h"

#include <chrono>
#include <exception>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace
{
using namespace space::ssh;

void expect_true(bool value, const std::string& message)
{
    if (!value)
    {
        throw std::runtime_error(message);
    }
}

template <typename T, typename U>
void expect_eq(const T& actual, const U& expected, const std::string& message)
{
    if (!(actual == expected))
    {
        throw std::runtime_error(message);
    }
}

ConnectOptions connect_options(uint64_t timeout_ms = 0)
{
    ConnectOptions options;
    options.target.host = "example.test";
    options.target.username = "tester";
    options.timeout_ms = timeout_ms;
    return options;
}

ExecOptions exec_options()
{
    ExecOptions options;
    options.command = "true";
    return options;
}

std::vector<Event> poll_until(Service& service, std::size_t expected, int max_attempts = 200)
{
    std::vector<Event> events;
    for (int attempt = 0; attempt < max_attempts && events.size() < expected; ++attempt)
    {
        auto next = service.poll(0);
        events.insert(events.end(), next.begin(), next.end());
        if (events.size() >= expected)
        {
            break;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    return events;
}

std::size_t count_kind(const std::vector<Event>& events, EventKind kind)
{
    std::size_t count = 0;
    for (const auto& event : events)
    {
        if (event.kind == kind)
        {
            ++count;
        }
    }
    return count;
}

class FakeBackend : public Backend
{
public:
    enum class Mode
    {
        ImmediateConnect,
        EmitThreeEvents,
        WaitForCancel,
        SleepPastTimeout,
        KnownHostChallenge
    };

    explicit FakeBackend(Mode mode)
        : mode_(mode)
    {
    }

    void connect(OperationContext& context, const ConnectOptions&) override
    {
        if (mode_ == Mode::EmitThreeEvents)
        {
            context.sink().emit(Event{ EventKind::OperationStarted, context.operation_id() });
            context.sink().emit(Event{ EventKind::ExecStdout, context.operation_id(), 0, 0, 0, {{ "index", "1" }} });
            context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id() });
            return;
        }

        if (mode_ == Mode::WaitForCancel)
        {
            while (!context.token().is_cancelled())
            {
                std::this_thread::sleep_for(std::chrono::milliseconds(5));
            }
            return;
        }

        if (mode_ == Mode::SleepPastTimeout)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
            context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id() });
            return;
        }

        if (mode_ == Mode::KnownHostChallenge)
        {
            context.sink().emit(Event{ EventKind::KnownHostChallenge, context.operation_id() });
            return;
        }

        const SessionId session_id = context.sink().allocate_session();
        context.sink().emit(Event{ EventKind::Connected, context.operation_id(), session_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    void resolve_known_host(OperationId operation_id, KnownHostDecision, OperationSink& sink) override
    {
        const SessionId session_id = sink.allocate_session();
        sink.emit(Event{ EventKind::Connected, operation_id, session_id });
        sink.emit(Event{ EventKind::OperationSuccess, operation_id, session_id });
    }

    void close_session(OperationContext& context, SessionId session_id) override
    {
        context.sink().emit(Event{ EventKind::SessionClosed, context.operation_id(), session_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    void exec(OperationContext& context, SessionId session_id, const ExecOptions&) override
    {
        context.sink().emit(Event{ EventKind::ExecComplete, context.operation_id(), session_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    void sftp_upload(OperationContext&, SessionId, const SftpTransferOptions&) override {}
    void sftp_download(OperationContext&, SessionId, const SftpTransferOptions&) override {}
    void open_shell(OperationContext&, SessionId, const ShellOptions&) override {}
    void channel_write(OperationContext& context, ChannelId channel_id, const std::string&) override
    {
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), 0, channel_id });
    }
    void channel_resize(OperationContext&, ChannelId, uint32_t, uint32_t) override {}
    void channel_close(OperationContext&, ChannelId) override {}
    void open_local_tunnel(OperationContext&, SessionId, const TunnelOptions&) override {}
    void open_remote_tunnel(OperationContext&, SessionId, const TunnelOptions&) override {}
    void close_tunnel(OperationContext& context, TunnelId tunnel_id) override
    {
        context.sink().emit(Event{ EventKind::TunnelClosed, context.operation_id(), 0, 0, tunnel_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), 0, 0, tunnel_id });
    }

private:
    Mode mode_;
};

void connect_returns_monotonic_operation_ids()
{
    Service service(std::make_unique<FakeBackend>(FakeBackend::Mode::ImmediateConnect));

    expect_eq(service.connect(connect_options()), OperationId{ 1 }, "first connect operation id");
    expect_eq(service.connect(connect_options()), OperationId{ 2 }, "second connect operation id");
}

void poll_preserves_event_order()
{
    Service service(std::make_unique<FakeBackend>(FakeBackend::Mode::EmitThreeEvents));

    const OperationId operation_id = service.connect(connect_options());
    auto events = poll_until(service, 3);

    expect_eq(events.size(), std::size_t{ 3 }, "expected three events");
    expect_eq(events[0].kind, EventKind::OperationStarted, "first event kind");
    expect_eq(events[1].kind, EventKind::ExecStdout, "second event kind");
    expect_eq(events[2].kind, EventKind::OperationSuccess, "third event kind");
    expect_eq(events[0].operation_id, operation_id, "operation id preserved");
}

void unavailable_backend_returns_structured_error()
{
    Service service(make_unavailable_backend("SSH backend not available"));

    service.connect(connect_options());
    auto events = poll_until(service, 1);

    expect_eq(events.size(), std::size_t{ 1 }, "expected unavailable backend error");
    expect_eq(events[0].kind, EventKind::OperationError, "unavailable event kind");
    expect_eq(events[0].error_code, ErrorCode::UnavailableBackend, "unavailable error code");
    expect_eq(events[0].fields.at("error-code"), std::string("unavailable-backend"), "unavailable error field");
    expect_true(events[0].message.find("SSH backend not available") != std::string::npos,
                "unavailable error message names reason");
}

void invalid_session_operations_fail_loudly()
{
    Service service(std::make_unique<FakeBackend>(FakeBackend::Mode::ImmediateConnect));

    service.exec(999, exec_options());
    service.close_session(999);
    service.channel_write(999, "x");
    service.close_tunnel(999);
    auto events = poll_until(service, 4);

    expect_eq(events.size(), std::size_t{ 4 }, "expected four invalid id errors");
    for (const auto& event : events)
    {
        expect_eq(event.kind, EventKind::OperationError, "invalid operation kind");
        expect_eq(event.error_code, ErrorCode::InvalidId, "invalid operation error code");
        expect_eq(event.fields.at("error-code"), std::string("invalid-id"), "invalid operation error field");
    }
}

void cancel_emits_cancelled_terminal_event()
{
    Service service(std::make_unique<FakeBackend>(FakeBackend::Mode::WaitForCancel));

    const OperationId operation_id = service.connect(connect_options());
    expect_true(service.cancel(operation_id), "cancel should accept active operation");
    auto events = poll_until(service, 1);

    expect_eq(count_kind(events, EventKind::OperationCancelled), std::size_t{ 1 }, "exactly one cancelled event");
    expect_true(!service.cancel(operation_id), "cancel should reject terminal operation");
}

void timeout_emits_timeout_terminal_event()
{
    Service service(std::make_unique<FakeBackend>(FakeBackend::Mode::SleepPastTimeout));

    service.connect(connect_options(1));
    auto events = poll_until(service, 1);

    expect_eq(count_kind(events, EventKind::OperationTimeout), std::size_t{ 1 }, "exactly one timeout event");
}

void known_host_challenge_blocks_until_resolution()
{
    Service service(std::make_unique<FakeBackend>(FakeBackend::Mode::KnownHostChallenge));

    const OperationId operation_id = service.connect(connect_options());
    auto challenge = poll_until(service, 1);
    expect_eq(challenge.size(), std::size_t{ 1 }, "expected known-host challenge");
    expect_eq(challenge[0].kind, EventKind::KnownHostChallenge, "challenge event kind");
    expect_true(service.poll(0).empty(), "connected event must wait for known-host resolution");

    expect_true(service.resolve_known_host(operation_id, KnownHostDecision::AcceptOnce), "resolve known host succeeds");
    auto connected = poll_until(service, 2);

    expect_eq(connected.size(), std::size_t{ 2 }, "expected connected and success after resolution");
    expect_eq(connected[0].kind, EventKind::Connected, "connected event kind");
    expect_eq(connected[1].kind, EventKind::OperationSuccess, "success event kind");
}

void run(const std::string& name, void (*test)())
{
    test();
    std::cout << "PASS " << name << "\n";
}

} // namespace

int main()
{
    try
    {
        run("connect_returns_monotonic_operation_ids", connect_returns_monotonic_operation_ids);
        run("poll_preserves_event_order", poll_preserves_event_order);
        run("unavailable_backend_returns_structured_error", unavailable_backend_returns_structured_error);
        run("invalid_session_operations_fail_loudly", invalid_session_operations_fail_loudly);
        run("cancel_emits_cancelled_terminal_event", cancel_emits_cancelled_terminal_event);
        run("timeout_emits_timeout_terminal_event", timeout_emits_timeout_terminal_event);
        run("known_host_challenge_blocks_until_resolution", known_host_challenge_blocks_until_resolution);
    }
    catch (const std::exception& ex)
    {
        std::cerr << "FAIL: " << ex.what() << "\n";
        return 1;
    }

    return 0;
}
