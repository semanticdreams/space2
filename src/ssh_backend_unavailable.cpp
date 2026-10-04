#include "ssh_backend.h"

#include <utility>

namespace space::ssh
{

namespace
{

class UnavailableBackend : public Backend
{
public:
    explicit UnavailableBackend(std::string reason)
        : reason_(std::move(reason))
    {
        if (reason_.empty())
        {
            reason_ = "SSH backend unavailable";
        }
    }

    void connect(OperationContext& context, const ConnectOptions&) override { unavailable(context); }
    void resolve_known_host(OperationId operation_id, KnownHostDecision, OperationSink& sink) override
    {
        sink.emit(unavailable_event(operation_id));
    }
    void close_session(OperationContext& context, SessionId) override { unavailable(context); }
    void exec(OperationContext& context, SessionId, const ExecOptions&) override { unavailable(context); }
    void sftp_upload(OperationContext& context, SessionId, const SftpTransferOptions&) override { unavailable(context); }
    void sftp_download(OperationContext& context, SessionId, const SftpTransferOptions&) override { unavailable(context); }
    void open_shell(OperationContext& context, SessionId, const ShellOptions&) override { unavailable(context); }
    void channel_write(OperationContext& context, ChannelId, const std::string&) override { unavailable(context); }
    void channel_resize(OperationContext& context, ChannelId, uint32_t, uint32_t) override { unavailable(context); }
    void channel_close(OperationContext& context, ChannelId) override { unavailable(context); }
    void open_local_tunnel(OperationContext& context, SessionId, const TunnelOptions&) override { unavailable(context); }
    void open_remote_tunnel(OperationContext& context, SessionId, const TunnelOptions&) override { unavailable(context); }
    void close_tunnel(OperationContext& context, TunnelId) override { unavailable(context); }

private:
    Event unavailable_event(OperationId operation_id) const
    {
        return Event{ EventKind::OperationError,
                      operation_id,
                      0,
                      0,
                      0,
                      {{ "error-code", error_code_to_string(ErrorCode::UnavailableBackend) }},
                      ErrorCode::UnavailableBackend,
                      reason_ };
    }

    void unavailable(OperationContext& context) const
    {
        context.sink().emit(unavailable_event(context.operation_id()));
    }

    std::string reason_;
};

} // namespace

std::unique_ptr<Backend> make_unavailable_backend(std::string reason)
{
    return std::make_unique<UnavailableBackend>(std::move(reason));
}

}
