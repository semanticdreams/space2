#include "ssh_service.h"

#include "ssh_backend_libssh.h"

#include <algorithm>
#include <functional>
#include <stdexcept>
#include <utility>

namespace space::ssh
{

namespace
{

bool terminal_kind(EventKind kind)
{
    return kind == EventKind::OperationSuccess ||
        kind == EventKind::OperationError ||
        kind == EventKind::OperationTimeout ||
        kind == EventKind::OperationCancelled;
}

bool secret_field_name(const std::string& key)
{
    return key.find("password") != std::string::npos ||
        key.find("passphrase") != std::string::npos ||
        key.find("secret") != std::string::npos ||
        key.find("token") != std::string::npos ||
        key.find("private-key") != std::string::npos;
}

constexpr uint64_t ChannelWriteTimeoutMs = 500;

std::map<std::string, std::string> error_fields(ErrorCode code)
{
    return {{ "error-code", error_code_to_string(code) }};
}

} // namespace

class Service::Token : public CancellationToken
{
public:
    Token(OperationId operation_id, uint64_t timeout_ms)
        : operation_id_(operation_id)
    {
        if (timeout_ms > 0)
        {
            has_deadline_ = true;
            deadline_ = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout_ms);
        }
    }

    OperationId operation_id() const override
    {
        return operation_id_;
    }

    bool is_cancelled() const override
    {
        return cancelled_.load();
    }

    bool is_expired() const override
    {
        return has_deadline_ && std::chrono::steady_clock::now() >= deadline_;
    }

    void cancel()
    {
        cancelled_.store(true);
    }

private:
    OperationId operation_id_;
    std::atomic<bool> cancelled_ { false };
    bool has_deadline_ { false };
    std::chrono::steady_clock::time_point deadline_;
};

struct Service::OperationState
{
    explicit OperationState(std::shared_ptr<Token> token)
        : token(std::move(token))
    {
    }

    std::shared_ptr<Token> token;
    bool terminal { false };
};

OperationContext::OperationContext(OperationId operation_id, OperationSink& sink, CancellationToken& token)
    : operation_id_(operation_id)
    , sink_(sink)
    , token_(token)
{
}

OperationId OperationContext::operation_id() const
{
    return operation_id_;
}

OperationSink& OperationContext::sink()
{
    return sink_;
}

CancellationToken& OperationContext::token()
{
    return token_;
}

bool Backend::available() const
{
    return true;
}

std::string Backend::missing_reason() const
{
    return {};
}

std::string error_code_to_string(ErrorCode code)
{
    switch (code)
    {
    case ErrorCode::None: return "none";
    case ErrorCode::UnavailableBackend: return "unavailable-backend";
    case ErrorCode::MalformedOptions: return "malformed-options";
    case ErrorCode::InvalidId: return "invalid-id";
    case ErrorCode::UnknownHost: return "unknown-host";
    case ErrorCode::ChangedHostKey: return "changed-host-key";
    case ErrorCode::AuthFailed: return "auth-failed";
    case ErrorCode::Timeout: return "timeout";
    case ErrorCode::Cancelled: return "cancelled";
    case ErrorCode::Closed: return "closed";
    case ErrorCode::Unsupported: return "unsupported";
    case ErrorCode::LocalFileError: return "local-file-error";
    case ErrorCode::RemoteFileError: return "remote-file-error";
    case ErrorCode::TunnelBindFailed: return "tunnel-bind-failed";
    case ErrorCode::BackendError: return "backend-error";
    }
    return "backend-error";
}

std::string event_kind_to_string(EventKind kind)
{
    switch (kind)
    {
    case EventKind::OperationStarted: return "operation-started";
    case EventKind::KnownHostChallenge: return "known-host-challenge";
    case EventKind::Connected: return "connected";
    case EventKind::SessionClosed: return "session-closed";
    case EventKind::ExecStdout: return "exec-stdout";
    case EventKind::ExecStderr: return "exec-stderr";
    case EventKind::ExecComplete: return "exec-complete";
    case EventKind::SftpProgress: return "sftp-progress";
    case EventKind::SftpComplete: return "sftp-complete";
    case EventKind::ShellOpened: return "shell-opened";
    case EventKind::ChannelData: return "channel-data";
    case EventKind::ChannelClosed: return "channel-closed";
    case EventKind::TunnelOpened: return "tunnel-opened";
    case EventKind::TunnelClosed: return "tunnel-closed";
    case EventKind::OperationSuccess: return "operation-success";
    case EventKind::OperationError: return "operation-error";
    case EventKind::OperationTimeout: return "operation-timeout";
    case EventKind::OperationCancelled: return "operation-cancelled";
    }
    return "operation-error";
}

std::map<std::string, std::string> redact_secret_fields(const std::map<std::string, std::string>& fields)
{
    std::map<std::string, std::string> redacted;
    for (const auto& [key, value] : fields)
    {
        redacted[key] = secret_field_name(key) ? "[redacted]" : value;
    }
    return redacted;
}

Service::Service(std::unique_ptr<Backend> backend)
    : backend_(std::move(backend))
{
    if (!backend_)
    {
        throw std::invalid_argument("ssh service requires a backend");
    }
}

Service::~Service()
{
    shutdown();
}

bool Service::available() const
{
    return backend_->available();
}

std::string Service::missing_reason() const
{
    return backend_->missing_reason();
}

std::unique_ptr<Backend> make_default_backend()
{
#if SPACE_HAS_LIBSSH
    return make_libssh_backend();
#else
    return make_unavailable_backend("libssh backend not available");
#endif
}

OperationId Service::connect(const ConnectOptions& options)
{
    if (options.target.host.empty())
    {
        const OperationId operation_id = next_operation_id_locked();
        std::lock_guard<std::mutex> lock(mutex_);
        queue_event_locked(malformed_options_event(operation_id, "connect target.host must be non-empty"));
        return operation_id;
    }

    const OperationId operation_id = start_operation(options.timeout_ms);
    dispatch(operation_id, options.timeout_ms, [this, options](OperationContext& context) {
        backend_->connect(context, options);
    });
    return operation_id;
}

bool Service::resolve_known_host(OperationId operation_id, KnownHostDecision decision)
{
    return dispatch_existing_operation(operation_id, [this, decision](OperationContext& context) {
        backend_->resolve_known_host(context, decision);
    });
}

OperationId Service::close_session(SessionId session_id)
{
    if (!is_session_known(session_id))
    {
        return enqueue_error(ErrorCode::InvalidId, "unknown SSH session id");
    }

    const OperationId operation_id = start_operation(0);
    dispatch(operation_id, 0, [this, session_id](OperationContext& context) {
        backend_->close_session(context, session_id);
    });
    return operation_id;
}

OperationId Service::exec(SessionId session_id, const ExecOptions& options)
{
    if (options.command.empty())
    {
        return enqueue_error(ErrorCode::MalformedOptions, "exec command must be non-empty");
    }
    if (!is_session_known(session_id))
    {
        return enqueue_error(ErrorCode::InvalidId, "unknown SSH session id");
    }

    const OperationId operation_id = start_operation(options.timeout_ms);
    dispatch(operation_id, options.timeout_ms, [this, session_id, options](OperationContext& context) {
        backend_->exec(context, session_id, options);
    });
    return operation_id;
}

OperationId Service::sftp_upload(SessionId session_id, const SftpTransferOptions& options)
{
    if (options.local_path.empty() || options.remote_path.empty())
    {
        return enqueue_error(ErrorCode::MalformedOptions, "sftp upload local_path and remote_path must be non-empty");
    }
    if (!is_session_known(session_id))
    {
        return enqueue_error(ErrorCode::InvalidId, "unknown SSH session id");
    }
    const OperationId operation_id = start_operation(options.timeout_ms);
    dispatch(operation_id, options.timeout_ms, [this, session_id, options](OperationContext& context) {
        backend_->sftp_upload(context, session_id, options);
    });
    return operation_id;
}

OperationId Service::sftp_download(SessionId session_id, const SftpTransferOptions& options)
{
    if (options.local_path.empty() || options.remote_path.empty())
    {
        return enqueue_error(ErrorCode::MalformedOptions, "sftp download local_path and remote_path must be non-empty");
    }
    if (!is_session_known(session_id))
    {
        return enqueue_error(ErrorCode::InvalidId, "unknown SSH session id");
    }
    const OperationId operation_id = start_operation(options.timeout_ms);
    dispatch(operation_id, options.timeout_ms, [this, session_id, options](OperationContext& context) {
        backend_->sftp_download(context, session_id, options);
    });
    return operation_id;
}

OperationId Service::open_shell(SessionId session_id, const ShellOptions& options)
{
    if (options.request_pty && (options.cols == 0 || options.rows == 0))
    {
        return enqueue_error(ErrorCode::MalformedOptions, "shell PTY rows and cols must be non-zero");
    }
    if (!is_session_known(session_id))
    {
        return enqueue_error(ErrorCode::InvalidId, "unknown SSH session id");
    }
    const OperationId operation_id = start_operation(options.timeout_ms);
    dispatch(operation_id, options.timeout_ms, [this, session_id, options](OperationContext& context) {
        backend_->open_shell(context, session_id, options);
    });
    return operation_id;
}

OperationId Service::channel_write(ChannelId channel_id, const std::string& data)
{
    if (is_shutdown())
    {
        return 0;
    }
    if (!is_channel_known(channel_id))
    {
        return enqueue_error(ErrorCode::InvalidId, "unknown SSH channel id");
    }
    const OperationId operation_id = start_operation(ChannelWriteTimeoutMs);
    dispatch(operation_id, ChannelWriteTimeoutMs, [this, channel_id, data](OperationContext& context) {
        backend_->channel_write(context, channel_id, data);
    });
    return operation_id;
}

OperationId Service::channel_resize(ChannelId channel_id, uint32_t cols, uint32_t rows)
{
    if (is_shutdown())
    {
        return 0;
    }
    if (!is_channel_known(channel_id))
    {
        return enqueue_error(ErrorCode::InvalidId, "unknown SSH channel id");
    }
    const OperationId operation_id = start_operation(0);
    dispatch(operation_id, 0, [this, channel_id, cols, rows](OperationContext& context) {
        backend_->channel_resize(context, channel_id, cols, rows);
    });
    return operation_id;
}

OperationId Service::channel_close(ChannelId channel_id)
{
    if (is_shutdown())
    {
        return 0;
    }
    if (!is_channel_known(channel_id))
    {
        return enqueue_error(ErrorCode::InvalidId, "unknown SSH channel id");
    }
    const OperationId operation_id = start_operation(0);
    dispatch(operation_id, 0, [this, channel_id](OperationContext& context) {
        backend_->channel_close(context, channel_id);
    });
    return operation_id;
}

OperationId Service::open_local_tunnel(SessionId session_id, const TunnelOptions& options)
{
    if (options.remote_host.empty() || options.remote_port == 0)
    {
        return enqueue_error(ErrorCode::MalformedOptions, "local tunnel remote_host and remote_port must be set");
    }
    if (!is_session_known(session_id))
    {
        return enqueue_error(ErrorCode::InvalidId, "unknown SSH session id");
    }
    const OperationId operation_id = start_operation(options.timeout_ms);
    dispatch(operation_id, options.timeout_ms, [this, session_id, options](OperationContext& context) {
        backend_->open_local_tunnel(context, session_id, options);
    });
    return operation_id;
}

OperationId Service::open_remote_tunnel(SessionId session_id, const TunnelOptions& options)
{
    if (options.remote_host.empty() || options.remote_port == 0)
    {
        return enqueue_error(ErrorCode::MalformedOptions, "remote tunnel remote_host and remote_port must be set");
    }
    if (!is_session_known(session_id))
    {
        return enqueue_error(ErrorCode::InvalidId, "unknown SSH session id");
    }
    const OperationId operation_id = start_operation(options.timeout_ms);
    dispatch(operation_id, options.timeout_ms, [this, session_id, options](OperationContext& context) {
        backend_->open_remote_tunnel(context, session_id, options);
    });
    return operation_id;
}

OperationId Service::close_tunnel(TunnelId tunnel_id)
{
    if (is_shutdown())
    {
        return 0;
    }
    if (!is_tunnel_known(tunnel_id))
    {
        return enqueue_error(ErrorCode::InvalidId, "unknown SSH tunnel id");
    }
    const OperationId operation_id = start_operation(0);
    dispatch(operation_id, 0, [this, tunnel_id](OperationContext& context) {
        backend_->close_tunnel(context, tunnel_id);
    });
    return operation_id;
}

void Backend::cancel_operation(OperationId)
{
}

bool Service::cancel(OperationId operation_id)
{
    return finish_operation(operation_id, EventKind::OperationCancelled, ErrorCode::Cancelled, "SSH operation cancelled");
}

std::vector<Event> Service::poll(std::size_t max_results)
{
    std::lock_guard<std::mutex> lock(mutex_);
    const std::size_t limit = max_results == 0 ? events_.size() : std::min(max_results, events_.size());
    std::vector<Event> result;
    result.reserve(limit);
    for (std::size_t i = 0; i < limit; ++i)
    {
        result.push_back(std::move(events_.front()));
        events_.pop_front();
    }
    return result;
}

void Service::shutdown()
{
    std::vector<std::thread> workers;
    std::vector<OperationId> active_operations;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (shutdown_)
        {
            return;
        }
        shutdown_ = true;
        active_operations.reserve(operations_.size());
        for (auto& [operation_id, operation] : operations_)
        {
            active_operations.push_back(operation_id);
            operation->terminal = true;
            operation->token->cancel();
        }
        operations_.clear();
        sessions_.clear();
        channels_.clear();
        tunnels_.clear();
        channel_sessions_.clear();
        tunnel_sessions_.clear();
        events_.clear();
        workers.swap(workers_);
    }

    for (OperationId operation_id : active_operations)
    {
        backend_->cancel_operation(operation_id);
    }

    for (auto& worker : workers)
    {
        if (worker.joinable())
        {
            worker.join();
        }
    }
}

void Service::emit(Event event)
{
    event.fields = redact_secret_fields(event.fields);

    std::lock_guard<std::mutex> lock(mutex_);
    if (shutdown_)
    {
        return;
    }

    if (event.operation_id != 0)
    {
        auto it = operations_.find(event.operation_id);
        if (it == operations_.end() || it->second->terminal)
        {
            return;
        }

        if (terminal_kind(event.kind))
        {
            it->second->terminal = true;
            it->second->token->cancel();
            operations_.erase(it);
        }
    }

    note_handles_for_event_locked(event);
    queue_event_locked(std::move(event));
}

SessionId Service::allocate_session()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (shutdown_)
    {
        return 0;
    }
    const SessionId id = next_session_id_++;
    return id;
}

ChannelId Service::allocate_channel()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (shutdown_)
    {
        return 0;
    }
    const ChannelId id = next_channel_id_++;
    return id;
}

TunnelId Service::allocate_tunnel()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (shutdown_)
    {
        return 0;
    }
    const TunnelId id = next_tunnel_id_++;
    return id;
}

OperationId Service::next_operation_id_locked()
{
    std::lock_guard<std::mutex> lock(mutex_);
    return next_operation_id_++;
}

OperationId Service::enqueue_error(ErrorCode code, std::string message)
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (shutdown_)
    {
        return 0;
    }
    const OperationId operation_id = next_operation_id_++;
    queue_event_locked(Event{ EventKind::OperationError, operation_id, 0, 0, 0, error_fields(code), code, std::move(message) });
    return operation_id;
}

OperationId Service::start_operation(uint64_t timeout_ms)
{
    std::lock_guard<std::mutex> lock(mutex_);
    const OperationId operation_id = next_operation_id_++;
    operations_.emplace(operation_id, std::make_shared<OperationState>(std::make_shared<Token>(operation_id, timeout_ms)));
    return operation_id;
}

void Service::dispatch(OperationId operation_id, uint64_t timeout_ms, std::function<void(OperationContext&)> work)
{
    std::shared_ptr<OperationState> state;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (shutdown_)
        {
            return;
        }
        state = operations_.at(operation_id);
        workers_.emplace_back([this, operation_id, state, work = std::move(work)]() mutable {
            run_backend_work(operation_id, state, std::move(work));
        });

        if (timeout_ms > 0)
        {
            workers_.emplace_back([this, operation_id, timeout_ms, state]() {
                const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout_ms);
                while (!state->token->is_cancelled() && std::chrono::steady_clock::now() < deadline)
                {
                    std::this_thread::sleep_for(std::chrono::milliseconds(1));
                }
                if (state->token->is_cancelled())
                {
                    return;
                }
                finish_operation(operation_id, EventKind::OperationTimeout, ErrorCode::Timeout, "SSH operation timed out");
            });
        }
    }
}

bool Service::dispatch_existing_operation(OperationId operation_id, std::function<void(OperationContext&)> work)
{
    std::shared_ptr<OperationState> state;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (shutdown_)
        {
            return false;
        }

        auto it = operations_.find(operation_id);
        if (it == operations_.end() || it->second->terminal)
        {
            return false;
        }

        state = it->second;
        workers_.emplace_back([this, operation_id, state, work = std::move(work)]() mutable {
            run_backend_work(operation_id, state, std::move(work));
        });
    }

    return true;
}

void Service::run_backend_work(OperationId operation_id, const std::shared_ptr<OperationState>& state, std::function<void(OperationContext&)> work)
{
    OperationContext context(operation_id, *this, *state->token);
    try
    {
        work(context);
    }
    catch (const std::exception&)
    {
        emit(Event{ EventKind::OperationError,
                    operation_id,
                    0,
                    0,
                    0,
                    error_fields(ErrorCode::BackendError),
                    ErrorCode::BackendError,
                    "SSH backend operation failed" });
    }
    catch (...)
    {
        emit(Event{ EventKind::OperationError,
                    operation_id,
                    0,
                    0,
                    0,
                    error_fields(ErrorCode::BackendError),
                    ErrorCode::BackendError,
                    "SSH backend operation failed" });
    }
}

bool Service::finish_operation(OperationId operation_id, EventKind kind, ErrorCode code, std::string message)
{
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (shutdown_)
        {
            return false;
        }

        auto it = operations_.find(operation_id);
        if (it == operations_.end() || it->second->terminal)
        {
            return false;
        }

        it->second->terminal = true;
        it->second->token->cancel();
        operations_.erase(it);
        queue_event_locked(Event{ kind, operation_id, 0, 0, 0, error_fields(code), code, std::move(message) });
    }

    backend_->cancel_operation(operation_id);
    return true;
}

bool Service::is_session_known(SessionId session_id) const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return sessions_.find(session_id) != sessions_.end();
}

bool Service::is_channel_known(ChannelId channel_id) const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return channels_.find(channel_id) != channels_.end();
}

bool Service::is_tunnel_known(TunnelId tunnel_id) const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return tunnels_.find(tunnel_id) != tunnels_.end();
}

bool Service::is_shutdown() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return shutdown_;
}

Event Service::malformed_options_event(OperationId operation_id, std::string message) const
{
    return Event{ EventKind::OperationError,
                  operation_id,
                  0,
                  0,
                  0,
                  error_fields(ErrorCode::MalformedOptions),
                  ErrorCode::MalformedOptions,
                  std::move(message) };
}

void Service::queue_event_locked(Event event)
{
    if (!shutdown_)
    {
        events_.push_back(std::move(event));
    }
}

void Service::note_handles_for_event_locked(const Event& event)
{
    if (event.kind == EventKind::Connected && event.session_id != 0)
    {
        sessions_.insert(event.session_id);
    }
    else if (event.kind == EventKind::SessionClosed && event.session_id != 0)
    {
        sessions_.erase(event.session_id);
        for (auto it = channel_sessions_.begin(); it != channel_sessions_.end();)
        {
            if (it->second == event.session_id)
            {
                channels_.erase(it->first);
                it = channel_sessions_.erase(it);
            }
            else
            {
                ++it;
            }
        }
        for (auto it = tunnel_sessions_.begin(); it != tunnel_sessions_.end();)
        {
            if (it->second == event.session_id)
            {
                tunnels_.erase(it->first);
                it = tunnel_sessions_.erase(it);
            }
            else
            {
                ++it;
            }
        }
    }
    else if (event.kind == EventKind::ShellOpened && event.channel_id != 0)
    {
        channels_.insert(event.channel_id);
        if (event.session_id != 0)
        {
            channel_sessions_[event.channel_id] = event.session_id;
        }
    }
    else if (event.kind == EventKind::ChannelClosed && event.channel_id != 0)
    {
        channels_.erase(event.channel_id);
        channel_sessions_.erase(event.channel_id);
    }
    else if (event.kind == EventKind::TunnelOpened && event.tunnel_id != 0)
    {
        tunnels_.insert(event.tunnel_id);
        if (event.session_id != 0)
        {
            tunnel_sessions_[event.tunnel_id] = event.session_id;
        }
    }
    else if (event.kind == EventKind::TunnelClosed && event.tunnel_id != 0)
    {
        tunnels_.erase(event.tunnel_id);
        tunnel_sessions_.erase(event.tunnel_id);
    }
}

}
