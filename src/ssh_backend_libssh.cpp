#include "ssh_backend_libssh.h"

#include <algorithm>
#include <map>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#if SPACE_HAS_LIBSSH
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <fcntl.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

#include <cerrno>
#include <cstring>
#include <libssh/libssh.h>
#include <libssh/sftp.h>

#include <atomic>
#include <chrono>
#include <fstream>
#include <memory>
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

#ifdef _WIN32
using SocketFd = SOCKET;
using SocketLength = int;
constexpr SocketFd InvalidSocketFd = INVALID_SOCKET;
constexpr int SocketShutdownBoth = SD_BOTH;

bool ensure_winsock_initialized()
{
    static const bool initialized = []() {
        WSADATA data {};
        return WSAStartup(MAKEWORD(2, 2), &data) == 0;
    }();
    return initialized;
}

int last_socket_error()
{
    return WSAGetLastError();
}

bool is_transient_socket_error(int error)
{
    return error == WSAEWOULDBLOCK || error == WSAEINTR;
}

bool set_socket_nonblocking(SocketFd fd)
{
    u_long mode = 1;
    return ioctlsocket(fd, FIONBIO, &mode) == 0;
}

void close_socket(SocketFd fd)
{
    if (fd != InvalidSocketFd)
    {
        closesocket(fd);
    }
}

void shutdown_and_close_socket(SocketFd fd)
{
    if (fd != InvalidSocketFd)
    {
        shutdown(fd, SocketShutdownBoth);
        closesocket(fd);
    }
}
#else
using SocketFd = int;
using SocketLength = socklen_t;
constexpr SocketFd InvalidSocketFd = -1;
constexpr int SocketShutdownBoth = SHUT_RDWR;

bool ensure_winsock_initialized()
{
    return true;
}

int last_socket_error()
{
    return errno;
}

bool is_transient_socket_error(int error)
{
    return error == EAGAIN || error == EWOULDBLOCK || error == EINTR;
}

bool set_socket_nonblocking(SocketFd fd)
{
    return fcntl(fd, F_SETFL, fcntl(fd, F_GETFL, 0) | O_NONBLOCK) == 0;
}

void close_socket(SocketFd fd)
{
    if (fd != InvalidSocketFd)
    {
        close(fd);
    }
}

void shutdown_and_close_socket(SocketFd fd)
{
    if (fd != InvalidSocketFd)
    {
        shutdown(fd, SocketShutdownBoth);
        close(fd);
    }
}
#endif

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

struct TunnelHandle
{
    SocketFd listener_fd { InvalidSocketFd };
    std::atomic<bool> running { true };

    TunnelHandle() = default;
    explicit TunnelHandle(SocketFd listener)
        : listener_fd(listener)
    {
    }

    TunnelHandle(const TunnelHandle&) = delete;
    TunnelHandle& operator=(const TunnelHandle&) = delete;

    TunnelHandle(TunnelHandle&& other) noexcept
        : listener_fd(other.listener_fd)
        , running(other.running.load())
    {
        other.listener_fd = InvalidSocketFd;
        other.running.store(false);
    }

    TunnelHandle& operator=(TunnelHandle&& other) noexcept
    {
        if (this != &other)
        {
            stop();
            listener_fd = other.listener_fd;
            running.store(other.running.load());
            other.listener_fd = InvalidSocketFd;
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
        if (listener_fd != InvalidSocketFd)
        {
            shutdown_and_close_socket(listener_fd);
            listener_fd = InvalidSocketFd;
        }
    }
};

struct SessionResource
{
    explicit SessionResource(SessionHandle session)
        : handle(std::move(session))
    {
    }

    std::mutex mutex;
    SessionHandle handle;
};

struct ActiveSessionResource
{
    explicit ActiveSessionResource(SessionHandle session)
        : handle(std::move(session))
    {
    }

    ActiveSessionResource(const ActiveSessionResource&) = delete;
    ActiveSessionResource& operator=(const ActiveSessionResource&) = delete;

    void request_close()
    {
        std::lock_guard<std::mutex> lock(mutex);
        handle.reset();
    }

    std::mutex mutex;
    SessionHandle handle;
};

struct ChannelResource
{
    explicit ChannelResource(ChannelHandle channel)
        : handle(std::move(channel))
    {
    }

    ~ChannelResource()
    {
        request_close();
        join();
    }

    ChannelResource(const ChannelResource&) = delete;
    ChannelResource& operator=(const ChannelResource&) = delete;

    bool valid()
    {
        std::lock_guard<std::mutex> lock(mutex);
        return handle.value != nullptr;
    }

    void request_close()
    {
        running.store(false);
        std::lock_guard<std::mutex> lock(mutex);
        handle.reset();
    }

    void join()
    {
        if (reader.joinable() && reader.get_id() != std::this_thread::get_id())
        {
            reader.join();
        }
        else if (reader.joinable())
        {
            reader.detach();
        }
    }

    std::mutex mutex;
    ChannelHandle handle;
    std::atomic<bool> running { true };
    std::thread reader;
};

struct SftpFileResource
{
    explicit SftpFileResource(sftp_file file)
        : value(file)
    {
    }

    ~SftpFileResource()
    {
        request_close();
    }

    SftpFileResource(const SftpFileResource&) = delete;
    SftpFileResource& operator=(const SftpFileResource&) = delete;

    bool valid()
    {
        std::lock_guard<std::mutex> lock(mutex);
        return value != nullptr;
    }

    void request_close()
    {
        std::lock_guard<std::mutex> lock(mutex);
        if (value)
        {
            sftp_close(value);
            value = nullptr;
        }
    }

    std::mutex mutex;
    sftp_file value { nullptr };
};

struct RelayResource
{
    RelayResource(SocketFd accepted_client, ChannelHandle remote_channel)
        : client_fd(accepted_client)
        , remote(std::move(remote_channel))
    {
    }

    ~RelayResource()
    {
        request_close();
    }

    RelayResource(const RelayResource&) = delete;
    RelayResource& operator=(const RelayResource&) = delete;

    bool running() const
    {
        return active.load();
    }

    SocketFd client()
    {
        std::lock_guard<std::mutex> lock(client_mutex);
        return client_fd;
    }

    void request_close()
    {
        active.store(false);
        close_client();
        std::lock_guard<std::mutex> lock(remote_mutex);
        remote.reset();
    }

    void close_client()
    {
        std::lock_guard<std::mutex> lock(client_mutex);
        if (client_fd != InvalidSocketFd)
        {
            shutdown_and_close_socket(client_fd);
            client_fd = InvalidSocketFd;
        }
    }

    std::mutex client_mutex;
    SocketFd client_fd { InvalidSocketFd };
    std::mutex remote_mutex;
    ChannelHandle remote;
    std::atomic<bool> active { true };
};

struct TunnelResource
{
    explicit TunnelResource(SocketFd listener)
        : handle(listener)
    {
    }

    ~TunnelResource()
    {
        stop();
        join();
    }

    TunnelResource(const TunnelResource&) = delete;
    TunnelResource& operator=(const TunnelResource&) = delete;

    void stop()
    {
        handle.stop();
        std::vector<std::shared_ptr<RelayResource>> relays;
        {
            std::lock_guard<std::mutex> lock(mutex);
            relays = active_relays;
        }
        for (const auto& relay : relays)
        {
            relay->request_close();
        }
    }

    void join()
    {
        if (worker.joinable() && worker.get_id() != std::this_thread::get_id())
        {
            worker.join();
        }
        else if (worker.joinable())
        {
            worker.detach();
        }
    }

    bool add_relay(const std::shared_ptr<RelayResource>& relay)
    {
        std::lock_guard<std::mutex> lock(mutex);
        if (!handle.running.load())
        {
            return false;
        }
        active_relays.push_back(relay);
        return true;
    }

    void remove_relay(const std::shared_ptr<RelayResource>& relay)
    {
        std::lock_guard<std::mutex> lock(mutex);
        active_relays.erase(std::remove(active_relays.begin(), active_relays.end(), relay), active_relays.end());
    }

    TunnelHandle handle;
    std::mutex mutex;
    std::vector<std::shared_ptr<RelayResource>> active_relays;
    std::thread worker;
};

class LibsshBackend : public Backend
{
public:
    ~LibsshBackend() override
    {
        std::vector<std::shared_ptr<ChannelResource>> channels;
        std::vector<std::shared_ptr<TunnelResource>> tunnels;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            for (auto& [_, tunnel] : tunnels_)
            {
                tunnels.push_back(tunnel);
            }
            for (auto& [_, channel] : channels_)
            {
                channels.push_back(channel);
            }
            tunnels_.clear();
            channels_.clear();
            sessions_.clear();
            pending_.clear();
            active_operations_.clear();
        }
        for (const auto& tunnel : tunnels)
        {
            tunnel->stop();
        }
        for (const auto& channel : channels)
        {
            channel->request_close();
        }
        for (const auto& tunnel : tunnels)
        {
            tunnel->join();
        }
        for (const auto& channel : channels)
        {
            channel->join();
        }
    }

    void connect(OperationContext& context, const ConnectOptions& options) override
    {
        auto session = std::make_shared<ActiveSessionResource>(SessionHandle(ssh_new()));
        if (!session->handle.value)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH backend failed to create a session"));
            return;
        }

        if (!configure_session(context, session->handle.value, options))
        {
            return;
        }

        if (!check_active(context))
        {
            return;
        }

        register_active_session(context.operation_id(), session);
        const bool connected = connect_nonblocking(context, session);
        unregister_active_session(context.operation_id(), session);
        if (!connected)
        {
            if (!check_active(context))
            {
                return;
            }
            context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH backend failed to connect"));
            return;
        }

        SessionHandle connected_session;
        {
            std::lock_guard<std::mutex> session_lock(session->mutex);
            connected_session = std::move(session->handle);
        }

        if (!connected_session.value)
        {
            if (!check_active(context))
            {
                return;
            }
            context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH backend failed to connect"));
            return;
        }

        if (!check_known_host(context, std::move(connected_session), options))
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
        std::vector<std::shared_ptr<ChannelResource>> channels;
        std::vector<std::shared_ptr<TunnelResource>> tunnels;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            channels = take_owned_channels_locked(session_id);
            tunnels = take_owned_tunnels_locked(session_id);
            sessions_.erase(session_id);
        }
        for (const auto& tunnel : tunnels)
        {
            tunnel->stop();
        }
        for (const auto& channel : channels)
        {
            channel->request_close();
        }
        for (const auto& tunnel : tunnels)
        {
            tunnel->join();
        }
        for (const auto& channel : channels)
        {
            channel->join();
        }
        context.sink().emit(Event{ EventKind::SessionClosed, context.operation_id(), session_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    void cancel_operation(OperationId operation_id) override
    {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            pending_.erase(operation_id);
        }
        ActiveOperation active = take_active_operation(operation_id);
        for (const auto& channel : active.channels)
        {
            channel->request_close();
        }
        for (const auto& file : active.sftp_files)
        {
            file->request_close();
        }
        for (const auto& session : active.sessions)
        {
            session->request_close();
        }
    }

    void exec(OperationContext& context, SessionId session_id, const ExecOptions& options) override
    {
        auto session = session_for_id(session_id);
        if (!session)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH session id"));
            return;
        }

        ChannelHandle raw_channel;
        {
            std::lock_guard<std::mutex> session_lock(session->mutex);
            raw_channel = ChannelHandle(ssh_channel_new(session->handle.value));
        }
        auto channel = std::make_shared<ChannelResource>(std::move(raw_channel));
        if (!channel->valid())
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH exec failed to open channel"));
            return;
        }
        {
            std::lock_guard<std::mutex> channel_lock(channel->mutex);
            if (ssh_channel_open_session(channel->handle.value) != SSH_OK)
            {
                context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH exec failed to open channel"));
                return;
            }
        }
        register_active_channel(context.operation_id(), channel);
        if (!check_active(context))
        {
            unregister_active_channel(context.operation_id(), channel);
            return;
        }
        {
            std::lock_guard<std::mutex> channel_lock(channel->mutex);
            if (!channel->handle.value)
            {
                unregister_active_channel(context.operation_id(), channel);
                context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH exec request failed"));
                return;
            }
            for (const auto& [key, value] : options.env)
            {
                if (ssh_channel_request_env(channel->handle.value, key.c_str(), value.c_str()) != SSH_OK)
                {
                    unregister_active_channel(context.operation_id(), channel);
                    auto fields = error_fields(ErrorCode::BackendError);
                    fields["env-key"] = key;
                    context.sink().emit(Event{ EventKind::OperationError, context.operation_id(), session_id, 0, 0, std::move(fields), ErrorCode::BackendError, "SSH exec environment request failed" });
                    return;
                }
            }
            if (ssh_channel_request_exec(channel->handle.value, options.command.c_str()) != SSH_OK)
            {
                unregister_active_channel(context.operation_id(), channel);
                context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH exec request failed"));
                return;
            }
        }

        std::vector<char> stdout_buffer(4096);
        std::vector<char> stderr_buffer(4096);
        bool stdout_open = true;
        bool stderr_open = true;
        while ((stdout_open || stderr_open) && check_active(context))
        {
            int stdout_bytes = SSH_EOF;
            int stderr_bytes = SSH_EOF;
            bool eof = false;
            {
                std::lock_guard<std::mutex> channel_lock(channel->mutex);
                if (!channel->handle.value)
                {
                    break;
                }
                stdout_bytes = stdout_open ? ssh_channel_read_timeout(channel->handle.value, stdout_buffer.data(), static_cast<uint32_t>(stdout_buffer.size()), 0, 25) : SSH_EOF;
                stderr_bytes = stderr_open ? ssh_channel_read_timeout(channel->handle.value, stderr_buffer.data(), static_cast<uint32_t>(stderr_buffer.size()), 1, 25) : SSH_EOF;
                eof = ssh_channel_is_eof(channel->handle.value);
            }
            if (stdout_bytes > 0)
            {
                context.sink().emit(Event{ EventKind::ExecStdout, context.operation_id(), session_id, 0, 0, {{ "data", std::string(stdout_buffer.data(), stdout_bytes) }} });
            }
            else if (stdout_bytes == SSH_ERROR)
            {
                unregister_active_channel(context.operation_id(), channel);
                context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH exec stdout read failed"));
                return;
            }
            else if (stdout_bytes == SSH_EOF)
            {
                stdout_open = false;
            }

            if (stderr_bytes > 0)
            {
                context.sink().emit(Event{ EventKind::ExecStderr, context.operation_id(), session_id, 0, 0, {{ "data", std::string(stderr_buffer.data(), stderr_bytes) }} });
            }
            else if (stderr_bytes == SSH_ERROR)
            {
                unregister_active_channel(context.operation_id(), channel);
                context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH exec stderr read failed"));
                return;
            }
            else if (stderr_bytes == SSH_EOF)
            {
                stderr_open = false;
            }

            if (eof)
            {
                stdout_open = false;
                stderr_open = false;
            }
        }

        if (!check_active(context))
        {
            unregister_active_channel(context.operation_id(), channel);
            return;
        }
        int exit_status = 0;
        {
            std::lock_guard<std::mutex> channel_lock(channel->mutex);
            exit_status = channel->handle.value ? ssh_channel_get_exit_status(channel->handle.value) : 0;
        }
        unregister_active_channel(context.operation_id(), channel);
        context.sink().emit(Event{ EventKind::ExecComplete, context.operation_id(), session_id, 0, 0, {{ "exit-status", std::to_string(exit_status) }} });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    void sftp_upload(OperationContext& context, SessionId session_id, const SftpTransferOptions& options) override
    {
        auto session = session_for_id(session_id);
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

        SftpHandle sftp(nullptr);
        {
            std::lock_guard<std::mutex> session_lock(session->mutex);
            sftp.value = sftp_new(session->handle.value);
        }
        if (!sftp.value || sftp_init(sftp.value) != SSH_OK)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::RemoteFileError, "SSH SFTP upload could not start SFTP"));
            return;
        }
        auto output = std::make_shared<SftpFileResource>(sftp_open(sftp.value, options.remote_path.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600));
        if (!output->valid())
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::RemoteFileError, "SSH SFTP upload could not open remote file"));
            return;
        }
        register_active_sftp_file(context.operation_id(), output);

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
                ssize_t written = -1;
                {
                    std::lock_guard<std::mutex> file_lock(output->mutex);
                    written = output->value ? sftp_write(output->value,
                                                         buffer.data() + total_written,
                                                         static_cast<size_t>(read - total_written))
                                            : -1;
                }
                if (written <= 0)
                {
                    unregister_active_sftp_file(context.operation_id(), output);
                    context.sink().emit(error_event(context.operation_id(), ErrorCode::RemoteFileError, "SSH SFTP upload write failed before all bytes were delivered"));
                    return;
                }
                total_written += written;
            }
            if (!check_active(context))
            {
                unregister_active_sftp_file(context.operation_id(), output);
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
            unregister_active_sftp_file(context.operation_id(), output);
            return;
        }
        unregister_active_sftp_file(context.operation_id(), output);
        context.sink().emit(Event{ EventKind::SftpComplete, context.operation_id(), session_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    void sftp_download(OperationContext& context, SessionId session_id, const SftpTransferOptions& options) override
    {
        auto session = session_for_id(session_id);
        if (!session)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH session id"));
            return;
        }
        SftpHandle sftp(nullptr);
        {
            std::lock_guard<std::mutex> session_lock(session->mutex);
            sftp.value = sftp_new(session->handle.value);
        }
        if (!sftp.value || sftp_init(sftp.value) != SSH_OK)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::RemoteFileError, "SSH SFTP download could not start SFTP"));
            return;
        }
        auto input = std::make_shared<SftpFileResource>(sftp_open(sftp.value, options.remote_path.c_str(), O_RDONLY, 0));
        if (!input->valid())
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::RemoteFileError, "SSH SFTP download could not open remote file"));
            return;
        }
        register_active_sftp_file(context.operation_id(), input);
        uint64_t total = 0;
        sftp_attributes attributes = nullptr;
        {
            std::lock_guard<std::mutex> file_lock(input->mutex);
            attributes = input->value ? sftp_fstat(input->value) : nullptr;
        }
        if (attributes)
        {
            total = attributes->size;
            sftp_attributes_free(attributes);
        }
        std::ofstream output(options.local_path, std::ios::binary | std::ios::trunc);
        if (!output)
        {
            unregister_active_sftp_file(context.operation_id(), input);
            context.sink().emit(error_event(context.operation_id(), ErrorCode::LocalFileError, "SSH SFTP download could not open local file"));
            return;
        }

        std::vector<char> buffer(32768);
        uint64_t bytes = 0;
        while (check_active(context))
        {
            int read = -1;
            {
                std::lock_guard<std::mutex> file_lock(input->mutex);
                read = input->value ? sftp_read(input->value, buffer.data(), buffer.size()) : -1;
            }
            if (read == 0)
            {
                break;
            }
            if (read < 0)
            {
                unregister_active_sftp_file(context.operation_id(), input);
                context.sink().emit(error_event(context.operation_id(), ErrorCode::RemoteFileError, "SSH SFTP download read failed"));
                return;
            }
            output.write(buffer.data(), read);
            if (!output)
            {
                unregister_active_sftp_file(context.operation_id(), input);
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
            unregister_active_sftp_file(context.operation_id(), input);
            return;
        }
        unregister_active_sftp_file(context.operation_id(), input);
        context.sink().emit(Event{ EventKind::SftpComplete, context.operation_id(), session_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    void open_shell(OperationContext& context, SessionId session_id, const ShellOptions& options) override
    {
        auto session = session_for_id(session_id);
        if (!session)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH session id"));
            return;
        }
        ChannelHandle raw_channel;
        {
            std::lock_guard<std::mutex> session_lock(session->mutex);
            raw_channel = ChannelHandle(ssh_channel_new(session->handle.value));
        }
        auto channel = std::make_shared<ChannelResource>(std::move(raw_channel));
        if (!channel->valid())
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH shell failed to open channel"));
            return;
        }
        {
            std::lock_guard<std::mutex> channel_lock(channel->mutex);
            if (ssh_channel_open_session(channel->handle.value) != SSH_OK)
            {
                context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH shell failed to open channel"));
                return;
            }
            if (options.request_pty && ssh_channel_request_pty_size(channel->handle.value, options.term.empty() ? "xterm" : options.term.c_str(), options.cols, options.rows) != SSH_OK)
            {
                context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH shell PTY request failed"));
                return;
            }
            if (ssh_channel_request_shell(channel->handle.value) != SSH_OK)
            {
                context.sink().emit(error_event(context.operation_id(), ErrorCode::BackendError, "SSH shell request failed"));
                return;
            }
        }
        const ChannelId channel_id = context.sink().allocate_channel();
        {
            std::lock_guard<std::mutex> lock(mutex_);
            session_channels_[session_id].push_back(channel_id);
            channels_.emplace(channel_id, channel);
        }
        channel->reader = std::thread([this, sink = &context.sink(), session_id, channel_id, channel]() {
            read_shell_channel(*sink, session_id, channel_id, channel);
        });
        context.sink().emit(Event{ EventKind::ShellOpened, context.operation_id(), session_id, channel_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id, channel_id });
    }

    void channel_write(OperationContext& context, ChannelId channel_id, const std::string& data) override
    {
        auto channel = channel_for_id(channel_id);
        if (!channel)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH channel id"));
            return;
        }
        register_active_channel(context.operation_id(), channel);
        std::size_t written = 0;
        while (written < data.size() && check_active(context))
        {
            int next = -1;
            {
                std::lock_guard<std::mutex> channel_lock(channel->mutex);
                if (channel->handle.value)
                {
                    ssh_channel_set_blocking(channel->handle.value, 0);
                    next = ssh_channel_write(channel->handle.value, data.data() + written, static_cast<uint32_t>(data.size() - written));
                    ssh_channel_set_blocking(channel->handle.value, 1);
                }
            }
            if (next == SSH_AGAIN)
            {
                std::this_thread::sleep_for(std::chrono::milliseconds(5));
                continue;
            }
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
        auto channel = channel_for_id(channel_id);
        if (!channel)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH channel id"));
            return;
        }
        int result = SSH_ERROR;
        {
            std::lock_guard<std::mutex> channel_lock(channel->mutex);
            result = channel->handle.value ? ssh_channel_change_pty_size(channel->handle.value, cols, rows) : SSH_ERROR;
        }
        if (result != SSH_OK)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::Closed, "SSH channel resize failed"));
            return;
        }
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), 0, channel_id });
    }

    void channel_close(OperationContext& context, ChannelId channel_id) override
    {
        std::shared_ptr<ChannelResource> channel;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            auto it = channels_.find(channel_id);
            if (it == channels_.end())
            {
                context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH channel id"));
                return;
            }
            channel = it->second;
            channels_.erase(it);
            for (auto& [_, channel_ids] : session_channels_)
            {
                channel_ids.erase(std::remove(channel_ids.begin(), channel_ids.end(), channel_id), channel_ids.end());
            }
        }
        channel->request_close();
        channel->join();
        context.sink().emit(Event{ EventKind::ChannelClosed, context.operation_id(), 0, channel_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), 0, channel_id });
    }

    void open_local_tunnel(OperationContext& context, SessionId session_id, const TunnelOptions& options) override
    {
        auto session = session_for_id(session_id);
        if (!session)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH session id"));
            return;
        }

        SocketFd listener = bind_local_listener(options);
        if (listener == InvalidSocketFd)
        {
            context.sink().emit(error_event(context.operation_id(), ErrorCode::TunnelBindFailed, "SSH local tunnel could not bind listener"));
            return;
        }

        const TunnelId tunnel_id = context.sink().allocate_tunnel();
        auto tunnel = std::make_shared<TunnelResource>(listener);
        {
            std::lock_guard<std::mutex> lock(mutex_);
            tunnels_.emplace(tunnel_id, tunnel);
            session_tunnels_[session_id].push_back(tunnel_id);
        }
        tunnel->worker = std::thread([this, sink = &context.sink(), session, session_id, tunnel_id, options, tunnel]() {
            accept_local_tunnel(*sink, session, session_id, tunnel_id, options, tunnel);
        });
        context.sink().emit(Event{ EventKind::TunnelOpened, context.operation_id(), session_id, 0, tunnel_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id, 0, tunnel_id });
    }
    void open_remote_tunnel(OperationContext& context, SessionId, const TunnelOptions&) override { emit_unsupported(context); }
    void close_tunnel(OperationContext& context, TunnelId tunnel_id) override
    {
        std::shared_ptr<TunnelResource> tunnel;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            auto it = tunnels_.find(tunnel_id);
            if (it == tunnels_.end())
            {
                context.sink().emit(error_event(context.operation_id(), ErrorCode::InvalidId, "unknown SSH tunnel id"));
                return;
            }
            tunnel = it->second;
            tunnels_.erase(it);
            erase_owned_tunnel_locked(tunnel_id);
        }
        tunnel->stop();
        tunnel->join();
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
        std::vector<std::shared_ptr<ActiveSessionResource>> sessions;
        std::vector<std::shared_ptr<ChannelResource>> channels;
        std::vector<std::shared_ptr<SftpFileResource>> sftp_files;
    };

    void register_active_session(OperationId operation_id, std::shared_ptr<ActiveSessionResource> session)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        active_operations_[operation_id].sessions.push_back(session);
    }

    void unregister_active_session(OperationId operation_id, const std::shared_ptr<ActiveSessionResource>& session)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = active_operations_.find(operation_id);
        if (it == active_operations_.end())
        {
            return;
        }
        auto& sessions = it->second.sessions;
        sessions.erase(std::remove(sessions.begin(), sessions.end(), session), sessions.end());
        erase_empty_active_operation_locked(it);
    }

    void register_active_channel(OperationId operation_id, std::shared_ptr<ChannelResource> channel)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        active_operations_[operation_id].channels.push_back(channel);
    }

    void unregister_active_channel(OperationId operation_id, const std::shared_ptr<ChannelResource>& channel)
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

    void register_active_sftp_file(OperationId operation_id, std::shared_ptr<SftpFileResource> file)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        active_operations_[operation_id].sftp_files.push_back(file);
    }

    void unregister_active_sftp_file(OperationId operation_id, const std::shared_ptr<SftpFileResource>& file)
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
        if (it->second.sessions.empty() && it->second.channels.empty() && it->second.sftp_files.empty())
        {
            active_operations_.erase(it);
        }
    }

    ActiveOperation take_active_operation(OperationId operation_id)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        ActiveOperation active;
        auto it = active_operations_.find(operation_id);
        if (it == active_operations_.end())
        {
            return active;
        }
        active = std::move(it->second);
        active_operations_.erase(it);
        return active;
    }

    std::vector<std::shared_ptr<ChannelResource>> take_owned_channels_locked(SessionId session_id)
    {
        std::vector<std::shared_ptr<ChannelResource>> channels;
        auto owned = session_channels_.find(session_id);
        if (owned == session_channels_.end())
        {
            return channels;
        }
        for (ChannelId channel_id : owned->second)
        {
            auto it = channels_.find(channel_id);
            if (it != channels_.end())
            {
                channels.push_back(it->second);
                channels_.erase(it);
            }
        }
        session_channels_.erase(owned);
        return channels;
    }

    std::vector<std::shared_ptr<TunnelResource>> take_owned_tunnels_locked(SessionId session_id)
    {
        std::vector<std::shared_ptr<TunnelResource>> tunnels;
        auto owned = session_tunnels_.find(session_id);
        if (owned == session_tunnels_.end())
        {
            return tunnels;
        }
        for (TunnelId tunnel_id : owned->second)
        {
            auto it = tunnels_.find(tunnel_id);
            if (it != tunnels_.end())
            {
                tunnels.push_back(it->second);
                tunnels_.erase(it);
            }
        }
        session_tunnels_.erase(owned);
        return tunnels;
    }

    void erase_owned_tunnel_locked(TunnelId tunnel_id)
    {
        for (auto& [_, tunnel_ids] : session_tunnels_)
        {
            tunnel_ids.erase(std::remove(tunnel_ids.begin(), tunnel_ids.end(), tunnel_id), tunnel_ids.end());
        }
    }

    void read_shell_channel(OperationSink& sink, SessionId session_id, ChannelId channel_id, std::shared_ptr<ChannelResource> channel)
    {
        std::vector<char> buffer(4096);
        while (channel->running.load())
        {
            int read = SSH_ERROR;
            bool eof = false;
            {
                std::lock_guard<std::mutex> channel_lock(channel->mutex);
                if (!channel->handle.value)
                {
                    return;
                }
                read = ssh_channel_read_timeout(channel->handle.value, buffer.data(), static_cast<uint32_t>(buffer.size()), 0, 25);
                eof = ssh_channel_is_eof(channel->handle.value);
            }
            if (read > 0)
            {
                sink.emit(Event{ EventKind::ChannelData, 0, session_id, channel_id, 0, {{ "data", std::string(buffer.data(), read) }} });
                continue;
            }
            if (read == SSH_ERROR || read == SSH_EOF || eof)
            {
                {
                    std::lock_guard<std::mutex> lock(mutex_);
                    auto it = channels_.find(channel_id);
                    if (it == channels_.end() || it->second != channel)
                    {
                        return;
                    }
                    channels_.erase(it);
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

    SocketFd bind_local_listener(const TunnelOptions& options)
    {
        if (!ensure_winsock_initialized())
        {
            return InvalidSocketFd;
        }
        SocketFd listener = socket(AF_INET, SOCK_STREAM, 0);
        if (listener == InvalidSocketFd)
        {
            return InvalidSocketFd;
        }
        int yes = 1;
        setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, reinterpret_cast<const char*>(&yes), sizeof(yes));
        sockaddr_in address {};
        address.sin_family = AF_INET;
        address.sin_port = htons(options.local_port);
        const std::string host = options.local_host.empty() ? "127.0.0.1" : options.local_host;
        if (inet_pton(AF_INET, host.c_str(), &address.sin_addr) != 1 || bind(listener, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0 || listen(listener, 16) != 0)
        {
            close_socket(listener);
            return InvalidSocketFd;
        }
        set_socket_nonblocking(listener);
        return listener;
    }

    void accept_local_tunnel(OperationSink& sink,
                             std::shared_ptr<SessionResource> session,
                             SessionId session_id,
                             TunnelId tunnel_id,
                             TunnelOptions options,
                             std::shared_ptr<TunnelResource> tunnel)
    {
        while (tunnel_running(tunnel_id, tunnel))
        {
            SocketFd listener = tunnel_listener(tunnel_id, tunnel);
            if (listener == InvalidSocketFd)
            {
                break;
            }
            sockaddr_in client_address {};
            SocketLength client_length = sizeof(client_address);
            SocketFd client = accept(listener, reinterpret_cast<sockaddr*>(&client_address), &client_length);
            if (client == InvalidSocketFd)
            {
                if (is_transient_socket_error(last_socket_error()))
                {
                    std::this_thread::sleep_for(std::chrono::milliseconds(10));
                    continue;
                }
                break;
            }
            set_socket_nonblocking(client);
            ChannelHandle remote;
            {
                std::lock_guard<std::mutex> session_lock(session->mutex);
                remote = ChannelHandle(ssh_channel_new(session->handle.value));
            }
            if (!remote.value)
            {
                close_socket(client);
                continue;
            }
            ssh_channel_set_blocking(remote.value, 0);
            auto relay = std::make_shared<RelayResource>(client, std::move(remote));
            if (!tunnel->add_relay(relay))
            {
                relay->request_close();
                continue;
            }
            bool opened = false;
            {
                std::lock_guard<std::mutex> session_lock(session->mutex);
                while (relay->running() && tunnel_running(tunnel_id, tunnel))
                {
                    int result = SSH_ERROR;
                    {
                        std::lock_guard<std::mutex> remote_lock(relay->remote_mutex);
                        if (!relay->remote.value)
                        {
                            break;
                        }
                        result = ssh_channel_open_forward(relay->remote.value, options.remote_host.c_str(), options.remote_port, options.local_host.c_str(), options.local_port);
                    }
                    if (result == SSH_OK)
                    {
                        opened = true;
                        break;
                    }
                    if (result != SSH_AGAIN)
                    {
                        break;
                    }
                    std::this_thread::sleep_for(std::chrono::milliseconds(1));
                }
            }
            if (!opened || !tunnel_running(tunnel_id, tunnel))
            {
                tunnel->remove_relay(relay);
                relay->request_close();
                continue;
            }
            relay_tunnel_connection(relay, tunnel_id, tunnel);
            tunnel->remove_relay(relay);
            relay->request_close();
        }
        bool emit_closed = false;
        {
            std::lock_guard<std::mutex> lock(mutex_);
            auto it = tunnels_.find(tunnel_id);
            emit_closed = it != tunnels_.end() && it->second == tunnel;
            if (emit_closed)
            {
                tunnels_.erase(it);
                erase_owned_tunnel_locked(tunnel_id);
            }
        }
        if (emit_closed)
        {
            sink.emit(Event{ EventKind::TunnelClosed, 0, session_id, 0, tunnel_id });
        }
    }

    bool tunnel_running(TunnelId tunnel_id, const std::shared_ptr<TunnelResource>& tunnel)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = tunnels_.find(tunnel_id);
        return it != tunnels_.end() && it->second == tunnel && tunnel->handle.running.load();
    }

    SocketFd tunnel_listener(TunnelId tunnel_id, const std::shared_ptr<TunnelResource>& tunnel)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = tunnels_.find(tunnel_id);
        return it == tunnels_.end() || it->second != tunnel ? InvalidSocketFd : tunnel->handle.listener_fd;
    }

    void relay_tunnel_connection(const std::shared_ptr<RelayResource>& relay, TunnelId tunnel_id, const std::shared_ptr<TunnelResource>& tunnel)
    {
        std::vector<char> buffer(8192);
        bool client_input_open = true;
        while (relay->running() && tunnel_running(tunnel_id, tunnel))
        {
            SocketFd client = relay->client();
            if (client == InvalidSocketFd)
            {
                break;
            }
            if (client_input_open)
            {
                fd_set reads;
                FD_ZERO(&reads);
                FD_SET(client, &reads);
                timeval timeout { 0, 25000 };
                const int ready = select(static_cast<int>(client + 1), &reads, nullptr, nullptr, &timeout);
                if (ready > 0 && FD_ISSET(client, &reads))
                {
                    const auto received = recv(client, buffer.data(), static_cast<int>(buffer.size()), 0);
                    if (received < 0 && !is_transient_socket_error(last_socket_error()))
                    {
                        break;
                    }
                    if (received == 0)
                    {
                        client_input_open = false;
                        std::lock_guard<std::mutex> remote_lock(relay->remote_mutex);
                        if (!relay->remote.value)
                        {
                            break;
                        }
                        if (ssh_channel_send_eof(relay->remote.value) == SSH_ERROR)
                        {
                            break;
                        }
                    }
                    else if (received > 0)
                    {
                        std::size_t sent = 0;
                        while (sent < static_cast<std::size_t>(received) && relay->running() && tunnel_running(tunnel_id, tunnel))
                        {
                            int written = SSH_ERROR;
                            {
                                std::lock_guard<std::mutex> remote_lock(relay->remote_mutex);
                                if (!relay->remote.value)
                                {
                                    return;
                                }
                                written = ssh_channel_write(relay->remote.value, buffer.data() + sent, static_cast<uint32_t>(received - sent));
                            }
                            if (written == SSH_AGAIN)
                            {
                                std::this_thread::sleep_for(std::chrono::milliseconds(1));
                                continue;
                            }
                            if (written <= 0)
                            {
                                return;
                            }
                            sent += static_cast<std::size_t>(written);
                        }
                    }
                }
            }
            int remote_read = SSH_ERROR;
            bool remote_eof = false;
            {
                std::lock_guard<std::mutex> remote_lock(relay->remote_mutex);
                if (!relay->remote.value)
                {
                    break;
                }
                remote_read = ssh_channel_read_timeout(relay->remote.value, buffer.data(), static_cast<uint32_t>(buffer.size()), 0, 1);
                remote_eof = ssh_channel_is_eof(relay->remote.value);
            }
            if (remote_read > 0)
            {
                std::size_t sent = 0;
                while (sent < static_cast<std::size_t>(remote_read) && relay->running() && tunnel_running(tunnel_id, tunnel))
                {
                    client = relay->client();
                    if (client == InvalidSocketFd)
                    {
                        return;
                    }
                    const auto written = send(client, buffer.data() + sent, static_cast<int>(static_cast<std::size_t>(remote_read) - sent), 0);
                    if (written < 0 && is_transient_socket_error(last_socket_error()))
                    {
                        std::this_thread::sleep_for(std::chrono::milliseconds(1));
                        continue;
                    }
                    if (written <= 0)
                    {
                        return;
                    }
                    sent += static_cast<std::size_t>(written);
                }
            }
            else if (remote_read == SSH_AGAIN)
            {
                if (remote_eof)
                {
                    break;
                }
                if (!client_input_open)
                {
                    std::this_thread::sleep_for(std::chrono::milliseconds(1));
                }
                continue;
            }
            else if (remote_read == SSH_ERROR || remote_read == SSH_EOF)
            {
                break;
            }
            if (remote_read == 0 && remote_eof)
            {
                break;
            }
        }
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

    bool connect_nonblocking(OperationContext& context, const std::shared_ptr<ActiveSessionResource>& session)
    {
        while (check_active(context))
        {
            int rc = SSH_ERROR;
            {
                std::lock_guard<std::mutex> session_lock(session->mutex);
                if (!session->handle.value)
                {
                    return false;
                }
                ssh_set_blocking(session->handle.value, 0);
                rc = ssh_connect(session->handle.value);
                if (rc == SSH_OK)
                {
                    ssh_set_blocking(session->handle.value, 1);
                    return true;
                }
            }

            if (rc != SSH_AGAIN)
            {
                return false;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
        }
        return false;
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

    std::map<std::string, std::string> known_host_challenge_fields(ssh_session session, const ConnectOptions& options, ErrorCode code)
    {
        auto fields = error_fields(code);
        fields["host"] = options.target.host;
        fields["port"] = std::to_string(options.target.port);
        fields["username"] = options.target.username;
        fields["known-hosts-path"] = options.known_hosts_path;
        fields["known-hosts-source"] = options.known_hosts_path.empty() ? "default" : "configured";
        fields["reason"] = error_code_to_string(code);

        ssh_key public_key = nullptr;
        if (session && ssh_get_server_publickey(session, &public_key) == SSH_OK && public_key)
        {
            const char* key_type = ssh_key_type_to_char(ssh_key_type(public_key));
            if (key_type)
            {
                fields["key-type"] = key_type;
            }

            unsigned char* hash = nullptr;
            size_t hash_length = 0;
            if (ssh_get_publickey_hash(public_key, SSH_PUBLICKEY_HASH_SHA256, &hash, &hash_length) == SSH_OK && hash)
            {
                char* fingerprint = ssh_get_hexa(hash, hash_length);
                if (fingerprint)
                {
                    fields["fingerprint"] = fingerprint;
                    ssh_string_free_char(fingerprint);
                }
                ssh_clean_pubkey_hash(&hash);
            }
            ssh_key_free(public_key);
        }
        return fields;
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
            auto fields = known_host_challenge_fields(session.value, options, code);
            {
                std::lock_guard<std::mutex> lock(mutex_);
                pending_[context.operation_id()] = PendingConnect{ std::move(session), options, code, message };
            }
            context.sink().emit(Event{ EventKind::KnownHostChallenge, context.operation_id(), 0, 0, 0, std::move(fields), code, message });
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
            sessions_.emplace(session_id, std::make_shared<SessionResource>(std::move(session)));
        }
        context.sink().emit(Event{ EventKind::Connected, context.operation_id(), session_id });
        context.sink().emit(Event{ EventKind::OperationSuccess, context.operation_id(), session_id });
    }

    std::shared_ptr<SessionResource> session_for_id(SessionId session_id)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = sessions_.find(session_id);
        return it == sessions_.end() ? nullptr : it->second;
    }

    std::shared_ptr<ChannelResource> channel_for_id(ChannelId channel_id)
    {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = channels_.find(channel_id);
        return it == channels_.end() ? nullptr : it->second;
    }

    std::mutex mutex_;
    std::map<OperationId, PendingConnect> pending_;
    std::map<OperationId, ActiveOperation> active_operations_;
    std::map<SessionId, std::shared_ptr<SessionResource>> sessions_;
    std::map<ChannelId, std::shared_ptr<ChannelResource>> channels_;
    std::map<TunnelId, std::shared_ptr<TunnelResource>> tunnels_;
    std::map<SessionId, std::vector<ChannelId>> session_channels_;
    std::map<SessionId, std::vector<TunnelId>> session_tunnels_;
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
