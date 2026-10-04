#include "ssh_backend_libssh.h"

#include <algorithm>
#include <map>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#if SPACE_HAS_LIBSSH
#include <arpa/inet.h>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <libssh/libssh.h>
#include <libssh/sftp.h>
#include <netinet/in.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>

#include <atomic>
#include <chrono>
#include <fstream>
#include <thread>
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

struct TunnelHandle
{
    int listener_fd { -1 };
    std::atomic<bool> running { true };

    TunnelHandle() = default;
    explicit TunnelHandle(int listener)
        : listener_fd(listener)
    {
    }

    TunnelHandle(const TunnelHandle&) = delete;
    TunnelHandle& operator=(const TunnelHandle&) = delete;

    TunnelHandle(TunnelHandle&& other) noexcept
        : listener_fd(other.listener_fd)
        , running(other.running.load())
    {
        other.listener_fd = -1;
        other.running.store(false);
    }

    TunnelHandle& operator=(TunnelHandle&& other) noexcept
    {
        if (this != &other)
        {
            stop();
            listener_fd = other.listener_fd;
            running.store(other.running.load());
            other.listener_fd = -1;
            other.running.store(false);
        }
        return *this;
    }

    ~TunnelHandle()
    {
        stop();
    }

    void stop()
    {
        running.store(false);
        if (listener_fd >= 0)
        {
            shutdown(listener_fd, SHUT_RDWR);
            close(listener_fd);
            listener_fd = -1;
        }
    }
};

class LibsshBackend : public Backend
{
public:
    ~LibsshBackend() override
    {
        std::vector<std::thread> workers;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            for (auto& [_, tunnel] : tunnels_)
            {
                tunnel.stop();
            }
            for (auto& [_, channel] : channels_)
            {
                channel.reset();
            }
            for (auto& [_, session] : sessions_)
            {
                session.reset();
            }
            for (auto& worker : workers_)
            {
                workers.push_back(std::move(worker));
            }
            workers_.clear();
            tunnels_.clear();
            channels_.clear();
            sessions_.clear();
            pending_.clear();
        }
        for (auto& worker : workers)
        {
            if (worker.joinable())
            {
                worker.join();
            }
        }
    }

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
            close_owned_channels_locked(session_id);
            close_owned_tunnels_locked(session_id);
            sessions_.erase(session_id);
        }
        context.sink().emit(Event{ EventKind::SessionClosed, context.operation_id(), session_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    void cancel_operation(OperationId operation_id) override
    {
        std::lock_guard<std::mutex> lock(mutex_);
        pending_.erase(operation_id);
        auto active = active_operations_.find(operation_id);
        if (active == active_operations_.end())
        {
            return;
        }
        for (ssh_channel channel : active->second.channels)
        {
            if (channel)
            {
                ssh_channel_close(channel);
            }
        }
        for (sftp_file file : active->second.sftp_files)
        {
            if (file)
            {
                sftp_close(file);
            }
        }
        active_operations_.erase(active);
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
        register_active_channel(context.operation_id(), channel.value);
        if (!check_active(context))
        {
            unregister_active_channel(context.operation_id(), channel.value);
            return;
        }
        if (ssh_channel_request_exec(channel.value, options.command.c_str()) != SSH_OK)
        {
            unregister_active_channel(context.operation_id(), channel.value);
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
                unregister_active_channel(context.operation_id(), channel.value);
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
                unregister_active_channel(context.operation_id(), channel.value);
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
            unregister_active_channel(context.operation_id(), channel.value);
            return;
        }
        const int exit_status = ssh_channel_get_exit_status(channel.value);
        unregister_active_channel(context.operation_id(), channel.value);
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
        register_active_sftp_file(context.operation_id(), output.value);

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
            std::streamsize total_written = 0;
            while (total_written < read && check_active(context))
            {
                const ssize_t written = sftp_write(output.value,
                                                  buffer.data() + total_written,
                                                  static_cast<size_t>(read - total_written));
                if (written <= 0)
                {
                    unregister_active_sftp_file(context.operation_id(), output.value);
                    context.sink().emit(error_event(context.operation_id(), ErrorCode::RemoteFileError, "SSH SFTP upload write failed before all bytes were delivered"));
                    return;
                }
                total_written += written;
            }
            if (!check_active(context))
            {
                unregister_active_sftp_file(context.operation_id(), output.value);
                return;
            }
            bytes += static_cast<uint64_t>(total_written);
            context.sink().emit(Event{ EventKind::SftpProgress,
                                        context.operation_id(),
                                        session_id,
                                        0,
                                        0,
                                        {{ "bytes", std::to_string(bytes) }, { "total-bytes", std::to_string(static_cast<uint64_t>(total)) }} });
        }
        if (!check_active(context))
        {
            unregister_active_sftp_file(context.operation_id(), output.value);
            return;
        }
        unregister_active_sftp_file(context.operation_id(), output.value);
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
        register_active_sftp_file(context.operation_id(), input.value);
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
                unregister_active_sftp_file(context.operation_id(), input.value);
                context.sink().emit(error_event(context.operation_id(), ErrorCode::RemoteFileError, "SSH SFTP download read failed"));
                return;
            }
            output.write(buffer.data(), read);
            if (!output)
            {
                unregister_active_sftp_file(context.operation_id(), input.value);
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
            unregister_active_sftp_file(context.operation_id(), input.value);
            return;
        }
        unregister_active_sftp_file(context.operation_id(), input.value);
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
            session_channels_[session_id].push_back(channel_id);
            channels_.emplace(channel_id, std::move(channel));
            workers_.emplace_back([this, sink = &context.sink(), session_id, channel_id]() {
                read_shell_channel(*sink, session_id, channel_id);
            });
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
        register_active_channel(context.operation_id(), channel);
        std::size_t written = 0;
        while (written < data.size() && check_active(context))
        {
            const int next = ssh_channel_write(channel, data.data() + written, static_cast<uint32_t>(data.size() - written));
            if (next <= 0)
            {
                unregister_active_channel(context.operation_id(), channel);
                context.sink().emit(error_event(context.operation_id(), ErrorCode::Closed, "SSH channel write failed before all bytes were delivered"));
                return;
            }
            written += static_cast<std::size_t>(next);
        }
        if (!check_active(context))
        {
            unregister_active_channel(context.operation_id(), channel);
            return;
        }
        unregister_active_channel(context.operation_id(), channel);
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
            for (auto& [_, channel_ids] : session_channels_)
            {
                channel_ids.erase(std::remove(channel_ids.begin(), channel_ids.end(), channel_id), channel_ids.end());
            }
        }
        context.sink().emit(Event{ EventKind::ChannelClosed, context.operation_id(), 0, channel_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), 0, channel_id });
    }

    void open_local_tunnel(OperationContext& context, SessionId session_id, const TunnelOptions& options) override
    {
        ssh_session session = session_for_id(session_id);
        if (!session)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH session id"));
            return;
        }

        int listener = bind_local_listener(options);
        if (listener < 0)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::TunnelBindFailed, "SSH local tunnel could not bind listener"));
            return;
        }

        const TunnelId tunnel_id = context.sink().allocate_tunnel();
        {
            std::lock_guard<std::mutex> lock(mutex_);
            tunnels_.emplace(tunnel_id, TunnelHandle(listener));
            session_tunnels_[session_id].push_back(tunnel_id);
            workers_.emplace_back([this, sink = &context.sink(), session, session_id, tunnel_id, options]() {
                accept_local_tunnel(*sink, session, session_id, tunnel_id, options);
            });
        }
        context.sink().emit(Event{ EventKind::TunnelOpened, context.operation_id(), session_id, 0, tunnel_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id, 0, tunnel_id });
    }
    void open_remote_tunnel(OperationContext& context, SessionId, const TunnelOptions&) override { emit_unsupported(context); }
    void close_tunnel(OperationContext& context, TunnelId tunnel_id) override
    {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            auto it = tunnels_.find(tunnel_id);
            if (it == tunnels_.end())
            {
                context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH tunnel id"));
                return;
            }
            it->second.stop();
            tunnels_.erase(it);
            erase_owned_tunnel_locked(tunnel_id);
        }
        context.sink().emit(Event{ EventKind::TunnelClosed, context.operation_id(), 0, 0, tunnel_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), 0, 0, tunnel_id });
    }

private:
    struct PendingConnect
    {
        SessionHandle session;
        ConnectOptions options;
        ErrorCode error_code { ErrorCode::UnknownHost };
        std::string error_message;
    };

    struct ActiveOperation
    {
        std::vector<ssh_channel> channels;
        std::vector<sftp_file> sftp_files;
    };

    void register_active_channel(OperationId operation_id, ssh_channel channel)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        active_operations_[operation_id].channels.push_back(channel);
    }

    void unregister_active_channel(OperationId operation_id, ssh_channel channel)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = active_operations_.find(operation_id);
        if (it == active_operations_.end())
        {
            return;
        }
        auto& channels = it->second.channels;
        channels.erase(std::remove(channels.begin(), channels.end(), channel), channels.end());
        erase_empty_active_operation_locked(it);
    }

    void register_active_sftp_file(OperationId operation_id, sftp_file file)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        active_operations_[operation_id].sftp_files.push_back(file);
    }

    void unregister_active_sftp_file(OperationId operation_id, sftp_file file)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = active_operations_.find(operation_id);
        if (it == active_operations_.end())
        {
            return;
        }
        auto& files = it->second.sftp_files;
        files.erase(std::remove(files.begin(), files.end(), file), files.end());
        erase_empty_active_operation_locked(it);
    }

    void erase_empty_active_operation_locked(std::map<OperationId, ActiveOperation>::iterator it)
    {
        if (it->second.channels.empty() && it->second.sftp_files.empty())
        {
            active_operations_.erase(it);
        }
    }

    void close_owned_channels_locked(SessionId session_id)
    {
        auto owned = session_channels_.find(session_id);
        if (owned == session_channels_.end())
        {
            return;
        }
        for (ChannelId channel_id : owned->second)
        {
            channels_.erase(channel_id);
        }
        session_channels_.erase(owned);
    }

    void close_owned_tunnels_locked(SessionId session_id)
    {
        auto owned = session_tunnels_.find(session_id);
        if (owned == session_tunnels_.end())
        {
            return;
        }
        for (TunnelId tunnel_id : owned->second)
        {
            auto it = tunnels_.find(tunnel_id);
            if (it != tunnels_.end())
            {
                it->second.stop();
                tunnels_.erase(it);
            }
        }
        session_tunnels_.erase(owned);
    }

    void erase_owned_tunnel_locked(TunnelId tunnel_id)
    {
        for (auto& [_, tunnel_ids] : session_tunnels_)
        {
            tunnel_ids.erase(std::remove(tunnel_ids.begin(), tunnel_ids.end(), tunnel_id), tunnel_ids.end());
        }
    }

    void read_shell_channel(OperationSink& sink, SessionId session_id, ChannelId channel_id)
    {
        std::vector<char> buffer(4096);
        while (true)
        {
            ssh_channel channel = channel_for_id(channel_id);
            if (!channel)
            {
                return;
            }
            const int read = ssh_channel_read_timeout(channel, buffer.data(), static_cast<uint32_t>(buffer.size()), 0, 25);
            if (read > 0)
            {
                sink.emit(Event{ EventKind::ChannelData, 0, session_id, channel_id, 0, {{ "data", std::string(buffer.data(), read) }} });
                continue;
            }
            if (read == SSH_ERROR || read == SSH_EOF || ssh_channel_is_eof(channel))
            {
                {
                    std::lock_guard<std::mutex> lock(mutex_);
                    channels_.erase(channel_id);
                    for (auto& [_, channel_ids] : session_channels_)
                    {
                        channel_ids.erase(std::remove(channel_ids.begin(), channel_ids.end(), channel_id), channel_ids.end());
                    }
                }
                sink.emit(Event{ EventKind::ChannelClosed, 0, session_id, channel_id });
                return;
            }
        }
    }

    int bind_local_listener(const TunnelOptions& options)
    {
        int listener = socket(AF_INET, SOCK_STREAM, 0);
        if (listener < 0)
        {
            return -1;
        }
        int yes = 1;
        setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
        sockaddr_in address {};
        address.sin_family = AF_INET;
        address.sin_port = htons(options.local_port);
        const std::string host = options.local_host.empty() ? "127.0.0.1" : options.local_host;
        if (inet_pton(AF_INET, host.c_str(), &address.sin_addr) != 1 || bind(listener, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 || listen(listener, 16) != 0)
        {
            close(listener);
            return -1;
        }
        fcntl(listener, F_SETFL, fcntl(listener, F_GETFL, 0) | O_NONBLOCK);
        return listener;
    }

    void accept_local_tunnel(OperationSink& sink, ssh_session session, SessionId session_id, TunnelId tunnel_id, TunnelOptions options)
    {
        while (tunnel_running(tunnel_id))
        {
            int listener = tunnel_listener(tunnel_id);
            if (listener < 0)
            {
                break;
            }
            sockaddr_in client_address {};
            socklen_t client_length = sizeof(client_address);
            int client = accept(listener, reinterpret_cast<sockaddr*>(&client_address), &client_length);
            if (client < 0)
            {
                if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)
                {
                    std::this_thread::sleep_for(std::chrono::milliseconds(10));
                    continue;
                }
                break;
            }
            ChannelHandle remote(ssh_channel_new(session));
            if (!remote.value || ssh_channel_open_forward(remote.value, options.remote_host.c_str(), options.remote_port, options.local_host.c_str(), options.local_port) != SSH_OK)
            {
                close(client);
                continue;
            }
            relay_tunnel_connection(client, remote.value, tunnel_id);
        }
        bool emit_closed = false;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            emit_closed = tunnels_.erase(tunnel_id) > 0;
            if (emit_closed)
            {
                erase_owned_tunnel_locked(tunnel_id);
            }
        }
        if (emit_closed)
        {
            sink.emit(Event{ EventKind::TunnelClosed, 0, session_id, 0, tunnel_id });
        }
    }

    bool tunnel_running(TunnelId tunnel_id)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = tunnels_.find(tunnel_id);
        return it != tunnels_.end() && it->second.running.load();
    }

    int tunnel_listener(TunnelId tunnel_id)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = tunnels_.find(tunnel_id);
        return it == tunnels_.end() ? -1 : it->second.listener_fd;
    }

    void relay_tunnel_connection(int client, ssh_channel remote, TunnelId tunnel_id)
    {
        std::vector<char> buffer(8192);
        while (tunnel_running(tunnel_id) && !ssh_channel_is_eof(remote))
        {
            fd_set reads;
            FD_ZERO(&reads);
            FD_SET(client, &reads);
            timeval timeout { 0, 25000 };
            const int ready = select(client + 1, &reads, nullptr, nullptr, &timeout);
            if (ready > 0 && FD_ISSET(client, &reads))
            {
                const ssize_t received = recv(client, buffer.data(), buffer.size(), 0);
                if (received <= 0)
                {
                    break;
                }
                std::size_t sent = 0;
                while (sent < static_cast<std::size_t>(received))
                {
                    const int written = ssh_channel_write(remote, buffer.data() + sent, static_cast<uint32_t>(received - sent));
                    if (written <= 0)
                    {
                        close(client);
                        return;
                    }
                    sent += static_cast<std::size_t>(written);
                }
            }
            const int remote_read = ssh_channel_read_timeout(remote, buffer.data(), static_cast<uint32_t>(buffer.size()), 0, 1);
            if (remote_read > 0)
            {
                std::size_t sent = 0;
                while (sent < static_cast<std::size_t>(remote_read))
                {
                    const ssize_t written = send(client, buffer.data() + sent, static_cast<size_t>(remote_read) - sent, 0);
                    if (written <= 0)
                    {
                        close(client);
                        return;
                    }
                    sent += static_cast<std::size_t>(written);
                }
            }
            else if (remote_read == SSH_ERROR || remote_read == SSH_EOF)
            {
                break;
            }
        }
        close(client);
    }

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
    std::map<OperationId, ActiveOperation> active_operations_;
    std::map<SessionId, SessionHandle> sessions_;
    std::map<ChannelId, ChannelHandle> channels_;
    std::map<TunnelId, TunnelHandle> tunnels_;
    std::map<SessionId, std::vector<ChannelId>> session_channels_;
    std::map<SessionId, std::vector<TunnelId>> session_tunnels_;
    std::vector<std::thread> workers_;
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
