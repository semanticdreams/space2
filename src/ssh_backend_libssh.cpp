#include "ssh_backend_libssh.h"

#include <map>
#include <mutex>
#include <string>
#include <utility>

#if SPACE_HAS_LIBSSH
#include <libssh/libssh.h>
#endif

namespace space::ssh
{

namespace
{

std::map<std::string, std::string> error_fields(ErrorCode code)
{
    return {{ "error-code", error_code_to_string(code) }};
}

Event error_event(OperationId operation_id, ErrorCode code, std::string message)
{
    return Event{ EventKind::OperationError, operation_id, 0, 0, 0, error_fields(code), code, std::move(message) };
}

void emit_unsupported(OperationContext& context)
{
    context.sink().emit(error_event(context.operation_id(), ErrorCode::Unsupported, "SSH operation is not implemented by this backend"));
}

#if SPACE_HAS_LIBSSH

struct SessionHandle
{
    ssh_session value { nullptr };

    SessionHandle() = default;
    explicit SessionHandle(ssh_session session)
        : value(session)
    {
    }

    ~SessionHandle()
    {
        reset();
    }

    SessionHandle(const SessionHandle&) = delete;
    SessionHandle& operator=(const SessionHandle&) = delete;

    SessionHandle(SessionHandle&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    SessionHandle& operator=(SessionHandle&& other) noexcept
    {
        if (this != &other)
        {
            reset();
            value = other.value;
            other.value = nullptr;
        }
        return *this;
    }

    void reset()
    {
        if (value)
        {
            ssh_disconnect(value);
            ssh_free(value);
            value = nullptr;
        }
    }
};

class LibsshBackend : public Backend
{
public:
    void connect(OperationContext& context, const ConnectOptions& options) override
    {
        SessionHandle session(ssh_new());
        if (!session.value)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH backend failed to create a session"));
            return;
        }

        if (!configure_session(context, session.value, options))
        {
            return;
        }

        if (!check_active(context))
        {
            return;
        }

        if (ssh_connect(session.value) != SSH_OK)
        {
            if (!check_active(context))
            {
                return;
            }
            context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH backend failed to connect"));
            return;
        }

        if (!check_known_host(context, std::move(session), options))
        {
            return;
        }
    }

    void resolve_known_host(OperationContext& context, KnownHostDecision decision) override
    {
        PendingConnect pending;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            auto it = pending_.find(context.operation_id());
            if (it == pending_.end())
            {
                context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH known-host challenge"));
                return;
            }
            pending = std::move(it->second);
            pending_.erase(it);
        }

        if (decision == KnownHostDecision::Reject)
        {
            context.sink().emit(error_event(context.operation_id(), pending.error_code, pending.error_message));
            return;
        }

        if (decision == KnownHostDecision::AcceptAndStore && ssh_session_update_known_hosts(pending.session.value) != SSH_OK)
        {
            if (!check_active(context))
            {
                return;
            }
            context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH backend failed to store known host"));
            return;
        }

        authenticate_and_register(context, std::move(pending.session), pending.options);
    }

    void close_session(OperationContext& context, SessionId session_id) override
    {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            sessions_.erase(session_id);
        }
        context.sink().emit(Event{ EventKind::SessionClosed, context.operation_id(), session_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    void cancel_operation(OperationId operation_id) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        pending_.erase(operation_id);
    }

    void exec(OperationContext& context, SessionId, const ExecOptions&) override { emit_unsupported(context); }
    void sftp_upload(OperationContext& context, SessionId, const SftpTransferOptions&) override { emit_unsupported(context); }
    void sftp_download(OperationContext& context, SessionId, const SftpTransferOptions&) override { emit_unsupported(context); }
    void open_shell(OperationContext& context, SessionId, const ShellOptions&) override { emit_unsupported(context); }
    void channel_write(OperationContext& context, ChannelId, const std::string&) override { emit_unsupported(context); }
    void channel_resize(OperationContext& context, ChannelId, uint32_t, uint32_t) override { emit_unsupported(context); }
    void channel_close(OperationContext& context, ChannelId) override { emit_unsupported(context); }
    void open_local_tunnel(OperationContext& context, SessionId, const TunnelOptions&) override { emit_unsupported(context); }
    void open_remote_tunnel(OperationContext& context, SessionId, const TunnelOptions&) override { emit_unsupported(context); }
    void close_tunnel(OperationContext& context, TunnelId) override { emit_unsupported(context); }

private:
    struct PendingConnect
    {
        SessionHandle session;
        ConnectOptions options;
        ErrorCode error_code { ErrorCode::UnknownHost };
        std::string error_message;
    };

    bool configure_session(OperationContext& context, ssh_session session, const ConnectOptions& options)
    {
        const int port = options.target.port;
        if (ssh_options_set(session, SSH_OPTIONS_HOST, options.target.host.c_str()) != SSH_OK ||
            ssh_options_set(session, SSH_OPTIONS_PORT, &port) != SSH_OK)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH backend failed to configure target"));
            return false;
        }
        if (!options.target.username.empty() && ssh_options_set(session, SSH_OPTIONS_USER, options.target.username.c_str()) != SSH_OK)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH backend failed to configure username"));
            return false;
        }
        if (!options.known_hosts_path.empty() && ssh_options_set(session, SSH_OPTIONS_KNOWNHOSTS, options.known_hosts_path.c_str()) != SSH_OK)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH backend failed to configure known-hosts path"));
            return false;
        }
        if (options.timeout_ms > 0)
        {
            const long seconds = static_cast<long>(options.timeout_ms / 1000);
            const long useconds = static_cast<long>((options.timeout_ms % 1000) * 1000);
            ssh_options_set(session, SSH_OPTIONS_TIMEOUT, &seconds);
            ssh_options_set(session, SSH_OPTIONS_TIMEOUT_USEC, &useconds);
        }
        return true;
    }

    bool check_active(OperationContext& context)
    {
        if (context.token().is_expired())
        {
            context.sink().emit(Event{ EventKind::OperationTimeout, context.operation_id(), 0, 0, 0, error_fields(ErrorCode::Timeout), ErrorCode::Timeout, "SSH operation timed out" });
            return false;
        }
        if (context.token().is_cancelled())
        {
            context.sink().emit(Event{ EventKind::OperationCancelled, context.operation_id(), 0, 0, 0, error_fields(ErrorCode::Cancelled), ErrorCode::Cancelled, "SSH operation cancelled" });
            return false;
        }
        return true;
    }

    bool check_known_host(OperationContext& context, SessionHandle session, const ConnectOptions& options)
    {
        const int state = ssh_session_is_known_server(session.value);
        if (!check_active(context))
        {
            return false;
        }
        if (state == SSH_KNOWN_HOSTS_OK)
        {
            authenticate_and_register(context, std::move(session), options);
            return true;
        }

        ErrorCode code = ErrorCode::BackendError;
        std::string message = "SSH known-host verification failed";
        if (state == SSH_KNOWN_HOSTS_CHANGED)
        {
            code = ErrorCode::ChangedHostKey;
            message = "SSH host key changed";
        }
        else if (state == SSH_KNOWN_HOSTS_UNKNOWN || state == SSH_KNOWN_HOSTS_NOT_FOUND)
        {
            code = ErrorCode::UnknownHost;
            message = "SSH host is unknown";
        }

        if ((code == ErrorCode::UnknownHost || code == ErrorCode::ChangedHostKey) && options.known_host_policy == KnownHostPolicy::Ask)
        {
            {
                std::lock_guard<std::mutex> lock(mutex_);
                pending_[context.operation_id()] = PendingConnect{ std::move(session), options, code, message };
            }
            context.sink().emit(Event{ EventKind::KnownHostChallenge, context.operation_id(), 0, 0, 0, error_fields(code), code, message });
            return false;
        }

        if ((code == ErrorCode::UnknownHost || code == ErrorCode::ChangedHostKey) && options.known_host_policy == KnownHostPolicy::AcceptAndStore)
        {
            if (ssh_session_update_known_hosts(session.value) != SSH_OK)
            {
                if (!check_active(context))
                {
                    return false;
                }
                context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH backend failed to store known host"));
                return false;
            }
            authenticate_and_register(context, std::move(session), options);
            return true;
        }

        if ((code == ErrorCode::UnknownHost || code == ErrorCode::ChangedHostKey) && options.known_host_policy == KnownHostPolicy::AcceptOnce)
        {
            authenticate_and_register(context, std::move(session), options);
            return true;
        }

        context.sink().emit(error_event(context.operation_id(), code, message));
        return false;
    }

    void authenticate_and_register(OperationContext& context, SessionHandle session, const ConnectOptions& options)
    {
        if (!check_active(context))
        {
            return;
        }

        bool authenticated = options.auth_methods.empty() && ssh_userauth_publickey_auto(session.value, nullptr, nullptr) == SSH_AUTH_SUCCESS;
        for (const auto& method : options.auth_methods)
        {
            if (authenticated)
            {
                break;
            }
            if (method.type == AuthMethodType::Agent)
            {
                authenticated = ssh_userauth_publickey_auto(session.value, nullptr, nullptr) == SSH_AUTH_SUCCESS;
            }
            else if (method.type == AuthMethodType::PrivateKey)
            {
                ssh_key key = nullptr;
                const char* passphrase = method.passphrase.empty() ? nullptr : method.passphrase.c_str();
                if (ssh_pki_import_privkey_file(method.key_path.c_str(), passphrase, nullptr, nullptr, &key) == SSH_OK)
                {
                    authenticated = ssh_userauth_publickey(session.value, nullptr, key) == SSH_AUTH_SUCCESS;
                    ssh_key_free(key);
                }
            }
            else if (method.type == AuthMethodType::Password)
            {
                authenticated = ssh_userauth_password(session.value, nullptr, method.password.c_str()) == SSH_AUTH_SUCCESS;
            }
        }

        if (!authenticated)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::AuthFailed, "SSH authentication failed"));
            return;
        }

        const SessionId session_id = context.sink().allocate_session();
        {
            std::lock_guard<std::mutex> lock(mutex_);
            sessions_.emplace(session_id, std::move(session));
        }
        context.sink().emit(Event{ EventKind::Connected, context.operation_id(), session_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    std::mutex mutex_;
    std::map<OperationId, PendingConnect> pending_;
    std::map<SessionId, SessionHandle> sessions_;
};

#endif

} // namespace

std::unique_ptr<Backend> make_libssh_backend()
{
#if SPACE_HAS_LIBSSH
    return std::make_unique<LibsshBackend>();
#else
    return make_unavailable_backend("libssh backend not available");
#endif
}

}
