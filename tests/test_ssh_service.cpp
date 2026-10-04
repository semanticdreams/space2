#include "ssh_backend.h"
#include "ssh_service.h"

#include <atomic>
#include <array>
#include <chrono>
#include <exception>
#include <fstream>
#include <iostream>
#include <iterator>
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
        EmitStdoutAfterTimeout,
        EmitBackendErrorAfterTimeout,
        EmitStdoutAfterCancel,
        AllocateThenError,
        KnownHostChallenge,
        BlockingKnownHostResolution,
        ThrowSecretException
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

        if (mode_ == Mode::EmitStdoutAfterTimeout)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
            context.sink().emit(Event{ EventKind::ExecStdout, context.operation_id(), 0, 0, 0, {{ "data", "late" }} });
            return;
        }

        if (mode_ == Mode::EmitBackendErrorAfterTimeout)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
            context.sink().emit(Event{ EventKind::OperationError,
                                        context.operation_id(),
                                        0,
                                        0,
                                        0,
                                        {{ "error-code", "backend-error" }},
                                        ErrorCode::BackendError,
                                        "backend reported late failure" });
            return;
        }

        if (mode_ == Mode::EmitStdoutAfterCancel)
        {
            while (!context.token().is_cancelled())
            {
                std::this_thread::sleep_for(std::chrono::milliseconds(5));
            }
            context.sink().emit(Event{ EventKind::ExecStdout, context.operation_id(), 0, 0, 0, {{ "data", "late" }} });
            return;
        }

        if (mode_ == Mode::AllocateThenError)
        {
            const SessionId session_id = context.sink().allocate_session();
            last_session_id_.store(session_id);
            context.sink().emit(Event{ EventKind::OperationError,
                                        context.operation_id(),
                                        session_id,
                                        0,
                                        0,
                                        {{ "error-code", "auth-failed" }},
                                        ErrorCode::AuthFailed,
                                        "authentication failed" });
            return;
        }

        if (mode_ == Mode::KnownHostChallenge)
        {
            context.sink().emit(Event{ EventKind::KnownHostChallenge, context.operation_id() });
            return;
        }

        if (mode_ == Mode::BlockingKnownHostResolution)
        {
            context.sink().emit(Event{ EventKind::KnownHostChallenge, context.operation_id() });
            return;
        }

        if (mode_ == Mode::ThrowSecretException)
        {
            throw std::runtime_error("backend failed with password=hunter2 and passphrase=opensesame");
        }

        const SessionId session_id = context.sink().allocate_session();
        context.sink().emit(Event{ EventKind::Connected, context.operation_id(), session_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    void resolve_known_host(OperationContext& context, KnownHostDecision) override
    {
        if (mode_ == Mode::BlockingKnownHostResolution)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        }
        const SessionId session_id = context.sink().allocate_session();
        context.sink().emit(Event{ EventKind::Connected, context.operation_id(), session_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    SessionId last_session_id() const
    {
        return last_session_id_.load();
    }

    int cancelled_operations() const
    {
        return cancelled_operations_.load();
    }

    void cancel_operation(OperationId) override
    {
        cancelled_operations_.fetch_add(1);
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
    std::atomic<SessionId> last_session_id_ { 0 };
    std::atomic<int> cancelled_operations_ { 0 };
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

void default_backend_factory_never_returns_null()
{
    auto backend = make_default_backend();

    expect_true(static_cast<bool>(backend), "default backend factory must return a backend");
}

void default_backend_reports_unavailable_when_libssh_missing()
{
#if SPACE_HAS_LIBSSH
    return;
#else
    Service service(make_default_backend());

    service.connect(connect_options());
    auto events = poll_until(service, 1);

    expect_eq(events.size(), std::size_t{ 1 }, "expected unavailable default backend error");
    expect_eq(events[0].kind, EventKind::OperationError, "default backend unavailable event kind");
    expect_eq(events[0].error_code, ErrorCode::UnavailableBackend, "default backend unavailable error code");
    expect_eq(events[0].fields.at("error-code"), std::string("unavailable-backend"), "default backend unavailable field");
    expect_eq(events[0].message, std::string("libssh backend not available"), "default backend unavailable reason");
#endif
}

std::string read_header(const std::string& path)
{
    std::ifstream input(path);
    if (!input)
    {
        input.open("../" + path);
    }
    if (!input)
    {
        throw std::runtime_error("failed to open " + path);
    }
    return std::string(std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>());
}

void public_headers_do_not_include_libssh_symbols()
{
    const std::array<std::string, 3> headers = {
        "src/ssh_types.h",
        "src/ssh_backend.h",
        "src/ssh_service.h",
    };
    const std::array<std::string, 4> forbidden = {
        "libssh",
        "ssh_session",
        "ssh_channel",
        "ssh_scp",
    };

    for (const auto& header : headers)
    {
        const std::string contents = read_header(header);
        for (const auto& symbol : forbidden)
        {
            expect_true(contents.find(symbol) == std::string::npos, header + " exposes " + symbol);
        }
    }
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

void late_non_terminal_events_after_timeout_are_suppressed()
{
    Service service(std::make_unique<FakeBackend>(FakeBackend::Mode::EmitStdoutAfterTimeout));

    service.connect(connect_options(1));
    auto timeout = poll_until(service, 1);
    expect_eq(count_kind(timeout, EventKind::OperationTimeout), std::size_t{ 1 }, "expected timeout event");

    std::this_thread::sleep_for(std::chrono::milliseconds(75));
    auto late = service.poll(0);
    expect_eq(count_kind(late, EventKind::ExecStdout), std::size_t{ 0 }, "late stdout after timeout must be suppressed");
}

void late_backend_error_after_timeout_is_reported_as_timeout()
{
    Service service(std::make_unique<FakeBackend>(FakeBackend::Mode::EmitBackendErrorAfterTimeout));

    service.connect(connect_options(1));
    auto timeout = poll_until(service, 1);

    expect_eq(timeout.size(), std::size_t{ 1 }, "expected one terminal event");
    expect_eq(timeout[0].kind, EventKind::OperationTimeout, "timeout must win over late backend error");
    expect_eq(timeout[0].error_code, ErrorCode::Timeout, "late backend error after timeout must remain timeout-classified");
}

void cancel_notifies_backend_for_pending_cleanup()
{
    auto backend = std::make_unique<FakeBackend>(FakeBackend::Mode::KnownHostChallenge);
    FakeBackend* backend_ptr = backend.get();
    Service service(std::move(backend));

    const OperationId operation_id = service.connect(connect_options());
    auto challenge = poll_until(service, 1);
    expect_eq(challenge.size(), std::size_t{ 1 }, "expected known-host challenge before cancel");
    expect_eq(challenge[0].kind, EventKind::KnownHostChallenge, "challenge event kind before cancel");

    expect_true(service.cancel(operation_id), "cancel should accept pending known-host operation");
    auto cancelled = poll_until(service, 1);

    expect_eq(count_kind(cancelled, EventKind::OperationCancelled), std::size_t{ 1 }, "expected cancelled event");
    expect_eq(backend_ptr->cancelled_operations(), 1, "backend must be notified to clean pending challenge resources");
}

void timeout_notifies_backend_for_pending_cleanup()
{
    auto backend = std::make_unique<FakeBackend>(FakeBackend::Mode::KnownHostChallenge);
    FakeBackend* backend_ptr = backend.get();
    Service service(std::move(backend));

    service.connect(connect_options(20));
    auto challenge = poll_until(service, 1);
    expect_eq(challenge.size(), std::size_t{ 1 }, "expected known-host challenge before timeout");
    expect_eq(challenge[0].kind, EventKind::KnownHostChallenge, "challenge event kind before timeout");

    auto timeout = poll_until(service, 1);

    expect_eq(count_kind(timeout, EventKind::OperationTimeout), std::size_t{ 1 }, "expected timeout after unresolved challenge");
    expect_eq(backend_ptr->cancelled_operations(), 1, "backend must be notified to clean timed-out challenge resources");
}

void late_non_terminal_events_after_cancel_are_suppressed()
{
    Service service(std::make_unique<FakeBackend>(FakeBackend::Mode::EmitStdoutAfterCancel));

    const OperationId operation_id = service.connect(connect_options());
    expect_true(service.cancel(operation_id), "cancel should accept active operation");
    auto cancelled = poll_until(service, 1);
    expect_eq(count_kind(cancelled, EventKind::OperationCancelled), std::size_t{ 1 }, "expected cancelled event");

    std::this_thread::sleep_for(std::chrono::milliseconds(25));
    auto late = service.poll(0);
    expect_eq(count_kind(late, EventKind::ExecStdout), std::size_t{ 0 }, "late stdout after cancel must be suppressed");
}

void allocated_session_is_not_live_after_failed_connect()
{
    auto backend = std::make_unique<FakeBackend>(FakeBackend::Mode::AllocateThenError);
    FakeBackend* backend_ptr = backend.get();
    Service service(std::move(backend));

    service.connect(connect_options());
    auto failed = poll_until(service, 1);
    expect_eq(count_kind(failed, EventKind::OperationError), std::size_t{ 1 }, "expected failed connect error");
    const SessionId failed_session_id = backend_ptr->last_session_id();
    expect_true(failed_session_id != 0, "backend allocated a provisional session id");

    service.exec(failed_session_id, exec_options());
    auto invalid = poll_until(service, 1);
    expect_eq(invalid.size(), std::size_t{ 1 }, "expected invalid session error");
    expect_eq(invalid[0].error_code, ErrorCode::InvalidId, "failed-connect session id must not become live");
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

void known_host_resolution_returns_before_backend_continuation_finishes()
{
    Service service(std::make_unique<FakeBackend>(FakeBackend::Mode::BlockingKnownHostResolution));

    const OperationId operation_id = service.connect(connect_options());
    auto challenge = poll_until(service, 1);
    expect_eq(challenge.size(), std::size_t{ 1 }, "expected known-host challenge");

    const auto before = std::chrono::steady_clock::now();
    expect_true(service.resolve_known_host(operation_id, KnownHostDecision::AcceptOnce), "resolve known host succeeds");
    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - before);
    expect_true(elapsed < std::chrono::milliseconds(50), "known-host resolution must not block on backend continuation");

    auto connected = poll_until(service, 2);
    expect_eq(connected.size(), std::size_t{ 2 }, "expected connected and success after async continuation");
}

void backend_exception_messages_are_sanitized()
{
    Service service(std::make_unique<FakeBackend>(FakeBackend::Mode::ThrowSecretException));

    service.connect(connect_options());
    auto events = poll_until(service, 1);

    expect_eq(events.size(), std::size_t{ 1 }, "expected backend exception error");
    expect_eq(events[0].kind, EventKind::OperationError, "exception event kind");
    expect_eq(events[0].error_code, ErrorCode::BackendError, "exception error code");
    expect_true(events[0].message.find("hunter2") == std::string::npos, "password text must be redacted");
    expect_true(events[0].message.find("opensesame") == std::string::npos, "passphrase text must be redacted");
    expect_true(events[0].message.find("password=") == std::string::npos, "password marker must be redacted");
    expect_true(events[0].message.find("passphrase=") == std::string::npos, "passphrase marker must be redacted");
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
        run("default_backend_factory_never_returns_null", default_backend_factory_never_returns_null);
        run("default_backend_reports_unavailable_when_libssh_missing", default_backend_reports_unavailable_when_libssh_missing);
        run("public_headers_do_not_include_libssh_symbols", public_headers_do_not_include_libssh_symbols);
        run("invalid_session_operations_fail_loudly", invalid_session_operations_fail_loudly);
        run("cancel_emits_cancelled_terminal_event", cancel_emits_cancelled_terminal_event);
        run("timeout_emits_timeout_terminal_event", timeout_emits_timeout_terminal_event);
        run("late_non_terminal_events_after_timeout_are_suppressed", late_non_terminal_events_after_timeout_are_suppressed);
        run("late_backend_error_after_timeout_is_reported_as_timeout", late_backend_error_after_timeout_is_reported_as_timeout);
        run("cancel_notifies_backend_for_pending_cleanup", cancel_notifies_backend_for_pending_cleanup);
        run("timeout_notifies_backend_for_pending_cleanup", timeout_notifies_backend_for_pending_cleanup);
        run("late_non_terminal_events_after_cancel_are_suppressed", late_non_terminal_events_after_cancel_are_suppressed);
        run("allocated_session_is_not_live_after_failed_connect", allocated_session_is_not_live_after_failed_connect);
        run("known_host_challenge_blocks_until_resolution", known_host_challenge_blocks_until_resolution);
        run("known_host_resolution_returns_before_backend_continuation_finishes", known_host_resolution_returns_before_backend_continuation_finishes);
        run("backend_exception_messages_are_sanitized", backend_exception_messages_are_sanitized);
    }
    catch (const std::exception& ex)
    {
        std::cerr << "FAIL: " << ex.what() << "\n";
        return 1;
    }

    return 0;
}
