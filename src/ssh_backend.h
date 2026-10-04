#pragma once

#include "ssh_types.h"

#include <memory>
#include <string>

namespace space::ssh
{

class OperationSink
{
public:
    virtual ~OperationSink() = default;

    virtual void emit(Event event) = 0;
    virtual SessionId allocate_session() = 0;
    virtual ChannelId allocate_channel() = 0;
    virtual TunnelId allocate_tunnel() = 0;
};

class CancellationToken
{
public:
    virtual ~CancellationToken() = default;

    virtual OperationId operation_id() const = 0;
    virtual bool is_cancelled() const = 0;
    virtual bool is_expired() const = 0;
};

class OperationContext
{
public:
    OperationContext(OperationId operation_id, OperationSink& sink, CancellationToken& token);

    OperationId operation_id() const;
    OperationSink& sink();
    CancellationToken& token();

private:
    OperationId operation_id_;
    OperationSink& sink_;
    CancellationToken& token_;
};

class Backend
{
public:
    virtual ~Backend() = default;

    virtual void connect(OperationContext& context, const ConnectOptions& options) = 0;
    virtual void resolve_known_host(OperationContext& context, KnownHostDecision decision) = 0;
    virtual void close_session(OperationContext& context, SessionId session_id) = 0;
    virtual void exec(OperationContext& context, SessionId session_id, const ExecOptions& options) = 0;
    virtual void sftp_upload(OperationContext& context, SessionId session_id, const SftpTransferOptions& options) = 0;
    virtual void sftp_download(OperationContext& context, SessionId session_id, const SftpTransferOptions& options) = 0;
    virtual void open_shell(OperationContext& context, SessionId session_id, const ShellOptions& options) = 0;
    virtual void channel_write(OperationContext& context, ChannelId channel_id, const std::string& data) = 0;
    virtual void channel_resize(OperationContext& context, ChannelId channel_id, uint32_t cols, uint32_t rows) = 0;
    virtual void channel_close(OperationContext& context, ChannelId channel_id) = 0;
    virtual void open_local_tunnel(OperationContext& context, SessionId session_id, const TunnelOptions& options) = 0;
    virtual void open_remote_tunnel(OperationContext& context, SessionId session_id, const TunnelOptions& options) = 0;
    virtual void close_tunnel(OperationContext& context, TunnelId tunnel_id) = 0;
};

std::unique_ptr<Backend> make_unavailable_backend(std::string reason);

}
