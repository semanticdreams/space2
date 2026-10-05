#pragma once

#include "ssh_backend.h"

#include <atomic>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace space::ssh
{

struct ServiceOptions
{
    uint64_t channel_write_timeout_ms { 60000 };
};

class Service : private OperationSink
{
public:
    explicit Service(std::unique_ptr<Backend> backend);
    Service(std::unique_ptr<Backend> backend, ServiceOptions options);
    ~Service();

    Service(const Service&) = delete;
    Service& operator=(const Service&) = delete;

    bool available() const;
    std::string missing_reason() const;

    OperationId connect(const ConnectOptions& options);
    bool resolve_known_host(OperationId operation_id, KnownHostDecision decision);
    OperationId close_session(SessionId session_id);
    OperationId exec(SessionId session_id, const ExecOptions& options);
    OperationId sftp_upload(SessionId session_id, const SftpTransferOptions& options);
    OperationId sftp_download(SessionId session_id, const SftpTransferOptions& options);
    OperationId open_shell(SessionId session_id, const ShellOptions& options);
    OperationId channel_write(ChannelId channel_id, const std::string& data);
    OperationId channel_resize(ChannelId channel_id, uint32_t cols, uint32_t rows);
    OperationId channel_close(ChannelId channel_id);
    OperationId open_local_tunnel(SessionId session_id, const TunnelOptions& options);
    OperationId open_remote_tunnel(SessionId session_id, const TunnelOptions& options);
    OperationId close_tunnel(TunnelId tunnel_id);
    bool cancel(OperationId operation_id);
    std::vector<Event> poll(std::size_t max_results = 0);
    void shutdown();

private:
    class Token;
    struct OperationState;

    void emit(Event event) override;
    SessionId allocate_session() override;
    ChannelId allocate_channel() override;
    TunnelId allocate_tunnel() override;

    OperationId next_operation_id_locked();
    OperationId enqueue_error(ErrorCode code, std::string message);
    OperationId start_operation(uint64_t timeout_ms);
    void dispatch(OperationId operation_id, uint64_t timeout_ms, std::function<void(OperationContext&)> work);
    bool dispatch_existing_operation(OperationId operation_id, std::function<void(OperationContext&)> work);
    void run_backend_work(OperationId operation_id, const std::shared_ptr<OperationState>& state, std::function<void(OperationContext&)> work);
    bool finish_operation(OperationId operation_id, EventKind terminal_kind, ErrorCode code, std::string message);
    bool is_session_known(SessionId session_id) const;
    bool is_channel_known(ChannelId channel_id) const;
    bool is_tunnel_known(TunnelId tunnel_id) const;
    bool is_shutdown() const;
    Event malformed_options_event(OperationId operation_id, std::string message) const;
    void queue_event_locked(Event event);
    void note_handles_for_event_locked(const Event& event);

    mutable std::mutex mutex_;
    std::unique_ptr<Backend> backend_;
    ServiceOptions options_;
    OperationId next_operation_id_ { 1 };
    SessionId next_session_id_ { 1 };
    ChannelId next_channel_id_ { 1 };
    TunnelId next_tunnel_id_ { 1 };
    std::unordered_map<OperationId, std::shared_ptr<OperationState>> operations_;
    std::unordered_set<SessionId> sessions_;
    std::unordered_set<ChannelId> channels_;
    std::unordered_set<TunnelId> tunnels_;
    std::unordered_map<ChannelId, SessionId> channel_sessions_;
    std::unordered_map<TunnelId, SessionId> tunnel_sessions_;
    std::deque<Event> events_;
    std::vector<std::thread> workers_;
    bool shutdown_ { false };
};

std::unique_ptr<Backend> make_default_backend();

}
