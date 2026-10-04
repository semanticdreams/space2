#include "ssh_backend_libssh.h"

#include <map>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#if SPACE_HAS_LIBSSH
#include <fcntl.h>
#include <libssh/libssh.h>
#include <libssh/sftp.h>

#include <fstream>
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

struct ChannelHandle
{
    ssh_channel value { nullptr };

    ChannelHandle() = default;
    explicit ChannelHandle(ssh_channel channel)
        : value(channel)
    {
    }

    ~ChannelHandle()
    {
        reset();
    }

    ChannelHandle(const ChannelHandle&) = delete;
    ChannelHandle& operator=(const ChannelHandle&) = delete;

    ChannelHandle(ChannelHandle&& other) noexcept
        : value(other.value)
    {
        other.value = nullptr;
    }

    ChannelHandle& operator=(ChannelHandle&& other) noexcept
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
            ssh_channel_send_eof(value);
            ssh_channel_close(value);
            ssh_channel_free(value);
            value = nullptr;
        }
    }
};

struct SftpHandle
{
    sftp_session value { nullptr };

    explicit SftpHandle(sftp_session sftp)
        : value(sftp)
    {
    }

    ~SftpHandle()
    {
        if (value)
        {
            sftp_free(value);
        }
    }
};

struct SftpFileHandle
{
    sftp_file value { nullptr };

    explicit SftpFileHandle(sftp_file file)
        : value(file)
    {
    }

    ~SftpFileHandle()
    {
        if (value)
        {
            sftp_close(value);
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

    void exec(OperationContext& context, SessionId session_id, const ExecOptions& options) override
    {
        ssh_session session = session_for_id(session_id);
        if (!session)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH session id"));
            return;
        }

        ChannelHandle channel(ssh_channel_new(session));
        if (!channel.value || ssh_channel_open_session(channel.value) != SSH_OK)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH exec failed to open channel"));
            return;
        }
        if (!check_active(context))
        {
            return;
        }
        if (ssh_channel_request_exec(channel.value, options.command.c_str()) != SSH_OK)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH exec request failed"));
            return;
        }

        std::vector<char> buffer(4096);
        bool stdout_open = true;
        bool stderr_open = true;
        while ((stdout_open || stderr_open) && check_active(context))
        {
            int stdout_bytes = stdout_open ? ssh_channel_read_timeout(channel.value, buffer.data(), static_cast<uint32_t>(buffer.size()), 0, 25) : SSH_EOF;
            if (stdout_bytes > 0)
            {
                context.sink().emit(Event{ EventKind::ExecStdout, context.operation_id(), session_id, 0, 0, {{ "data", std::string(buffer.data(), stdout_bytes) }} });
            }
            else if (stdout_bytes == SSH_ERROR)
            {
                context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH exec stdout read failed"));
                return;
            }
            else if (stdout_bytes == SSH_EOF)
            {
                stdout_open = false;
            }

            int stderr_bytes = stderr_open ? ssh_channel_read_timeout(channel.value, buffer.data(), static_cast<uint32_t>(buffer.size()), 1, 25) : SSH_EOF;
            if (stderr_bytes > 0)
            {
                context.sink().emit(Event{ EventKind::ExecStderr, context.operation_id(), session_id, 0, 0, {{ "data", std::string(buffer.data(), stderr_bytes) }} });
            }
            else if (stderr_bytes == SSH_ERROR)
            {
                context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH exec stderr read failed"));
                return;
            }
            else if (stderr_bytes == SSH_EOF)
            {
                stderr_open = false;
            }

            if (ssh_channel_is_eof(channel.value))
            {
                stdout_open = false;
                stderr_open = false;
            }
        }

        if (!check_active(context))
        {
            return;
        }
        const int exit_status = ssh_channel_get_exit_status(channel.value);
        context.sink().emit(Event{ EventKind::ExecComplete, context.operation_id(), session_id, 0, 0, {{ "exit-status", std::to_string(exit_status) }} });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    void sftp_upload(OperationContext& context, SessionId session_id, const SftpTransferOptions& options) override
    {
        ssh_session session = session_for_id(session_id);
        if (!session)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH session id"));
            return;
        }
        std::ifstream input(options.local_path, std::ios::binary);
        if (!input)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::LocalFileError, "SSH SFTP upload could not open local file"));
            return;
        }
        input.seekg(0, std::ios::end);
        const std::streamoff total = input.tellg();
        input.seekg(0, std::ios::beg);

        SftpHandle sftp(sftp_new(session));
        if (!sftp.value || sftp_init(sftp.value) != SSH_OK)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::RemoteFileError, "SSH SFTP upload could not start SFTP"));
            return;
        }
        SftpFileHandle output(sftp_open(sftp.value, options.remote_path.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600));
        if (!output.value)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::RemoteFileError, "SSH SFTP upload could not open remote file"));
            return;
        }

        std::vector<char> buffer(32768);
        uint64_t bytes = 0;
        while (input && check_active(context))
        {
            input.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
            const std::streamsize read = input.gcount();
            if (read <= 0)
            {
                break;
            }
            const ssize_t written = sftp_write(output.value, buffer.data(), static_cast<size_t>(read));
            if (written != read)
            {
                context.sink().emit(error_event(context.operation_id(), ErrorCode::RemoteFileError, "SSH SFTP upload write failed"));
                return;
            }
            bytes += static_cast<uint64_t>(written);
            context.sink().emit(Event{ EventKind::SftpProgress,
                                        context.operation_id(),
                                        session_id,
                                        0,
                                        0,
                                        {{ "bytes", std::to_string(bytes) }, { "total-bytes", std::to_string(static_cast<uint64_t>(total)) }} });
        }
        if (!check_active(context))
        {
            return;
        }
        context.sink().emit(Event{ EventKind::SftpComplete, context.operation_id(), session_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    void sftp_download(OperationContext& context, SessionId session_id, const SftpTransferOptions& options) override
    {
        ssh_session session = session_for_id(session_id);
        if (!session)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH session id"));
            return;
        }
        SftpHandle sftp(sftp_new(session));
        if (!sftp.value || sftp_init(sftp.value) != SSH_OK)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::RemoteFileError, "SSH SFTP download could not start SFTP"));
            return;
        }
        SftpFileHandle input(sftp_open(sftp.value, options.remote_path.c_str(), O_RDONLY, 0));
        if (!input.value)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::RemoteFileError, "SSH SFTP download could not open remote file"));
            return;
        }
        uint64_t total = 0;
        sftp_attributes attributes = sftp_fstat(input.value);
        if (attributes)
        {
            total = attributes->size;
            sftp_attributes_free(attributes);
        }
        std::ofstream output(options.local_path, std::ios::binary | std::ios::trunc);
        if (!output)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::LocalFileError, "SSH SFTP download could not open local file"));
            return;
        }

        std::vector<char> buffer(32768);
        uint64_t bytes = 0;
        while (check_active(context))
        {
            const int read = sftp_read(input.value, buffer.data(), buffer.size());
            if (read == 0)
            {
                break;
            }
            if (read < 0)
            {
                context.sink().emit(error_event(context.operation_id(), ErrorCode::RemoteFileError, "SSH SFTP download read failed"));
                return;
            }
            output.write(buffer.data(), read);
            if (!output)
            {
                context.sink().emit(error_event(context.operation_id(), ErrorCode::LocalFileError, "SSH SFTP download write failed"));
                return;
            }
            bytes += static_cast<uint64_t>(read);
            if (total > 0)
            {
                context.sink().emit(Event{ EventKind::SftpProgress,
                                            context.operation_id(),
                                            session_id,
                                            0,
                                            0,
                                            {{ "bytes", std::to_string(bytes) }, { "total-bytes", std::to_string(total) }} });
            }
        }
        if (!check_active(context))
        {
            return;
        }
        context.sink().emit(Event{ EventKind::SftpComplete, context.operation_id(), session_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    void open_shell(OperationContext& context, SessionId session_id, const ShellOptions& options) override
    {
        ssh_session session = session_for_id(session_id);
        if (!session)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH session id"));
            return;
        }
        ChannelHandle channel(ssh_channel_new(session));
        if (!channel.value || ssh_channel_open_session(channel.value) != SSH_OK)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH shell failed to open channel"));
            return;
        }
        if (options.request_pty && ssh_channel_request_pty_size(channel.value, options.term.empty() ? "xterm" : options.term.c_str(), options.cols, options.rows) != SSH_OK)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH shell PTY request failed"));
            return;
        }
        if (ssh_channel_request_shell(channel.value) != SSH_OK)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH shell request failed"));
            return;
        }
        const ChannelId channel_id = context.sink().allocate_channel();
        {
            std::lock_guard<std::mutex> lock(mutex_);
            channels_.emplace(channel_id, std::move(channel));
        }
        context.sink().emit(Event{ EventKind::ShellOpened, context.operation_id(), session_id, channel_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id, channel_id });
    }

    void channel_write(OperationContext& context, ChannelId channel_id, const std::string& data) override
    {
        ssh_channel channel = channel_for_id(channel_id);
        if (!channel)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH channel id"));
            return;
        }
        if (ssh_channel_write(channel, data.data(), data.size()) == SSH_ERROR)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::Closed, "SSH channel write failed"));
            return;
        }
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), 0, channel_id });
    }

    void channel_resize(OperationContext& context, ChannelId channel_id, uint32_t cols, uint32_t rows) override
    {
        ssh_channel channel = channel_for_id(channel_id);
        if (!channel)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH channel id"));
            return;
        }
        if (ssh_channel_change_pty_size(channel, cols, rows) != SSH_OK)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::Closed, "SSH channel resize failed"));
            return;
        }
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), 0, channel_id });
    }

    void channel_close(OperationContext& context, ChannelId channel_id) override
    {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            auto it = channels_.find(channel_id);
            if (it == channels_.end())
            {
                context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH channel id"));
                return;
            }
            channels_.erase(it);
        }
        context.sink().emit(Event{ EventKind::ChannelClosed, context.operation_id(), 0, channel_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), 0, channel_id });
    }

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

    ssh_session session_for_id(SessionId session_id)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = sessions_.find(session_id);
        return it == sessions_.end() ? nullptr : it->second.value;
    }

    ssh_channel channel_for_id(ChannelId channel_id)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = channels_.find(channel_id);
        return it == channels_.end() ? nullptr : it->second.value;
    }

    std::mutex mutex_;
    std::map<OperationId, PendingConnect> pending_;
    std::map<SessionId, SessionHandle> sessions_;
    std::map<ChannelId, ChannelHandle> channels_;
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
