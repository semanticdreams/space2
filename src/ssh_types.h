#pragma once

#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace space::ssh
{

using OperationId = uint64_t;
using SessionId = uint64_t;
using ChannelId = uint64_t;
using TunnelId = uint64_t;

enum class AuthMethodType { Agent, PrivateKey, Password };
enum class KnownHostPolicy { Reject, Ask, AcceptOnce, AcceptAndStore };
enum class KnownHostDecision { Reject, AcceptOnce, AcceptAndStore };

enum class ErrorCode
{
    None,
    UnavailableBackend,
    MalformedOptions,
    InvalidId,
    UnknownHost,
    ChangedHostKey,
    AuthFailed,
    Timeout,
    Cancelled,
    Closed,
    Unsupported,
    LocalFileError,
    RemoteFileError,
    TunnelBindFailed,
    BackendError
};

enum class EventKind
{
    OperationStarted,
    KnownHostChallenge,
    Connected,
    SessionClosed,
    ExecStdout,
    ExecStderr,
    ExecComplete,
    SftpProgress,
    SftpComplete,
    ShellOpened,
    ChannelData,
    ChannelClosed,
    TunnelOpened,
    TunnelClosed,
    OperationSuccess,
    OperationError,
    OperationTimeout,
    OperationCancelled
};

struct Target
{
    std::string host;
    uint16_t port { 22 };
    std::string username;
};

struct AuthMethod
{
    AuthMethodType type { AuthMethodType::Agent };
    std::string key_path;
    std::string passphrase;
    std::string password;
};

struct ConnectOptions
{
    Target target;
    std::vector<AuthMethod> auth_methods;
    std::string known_hosts_path;
    uint64_t timeout_ms { 0 };
    KnownHostPolicy known_host_policy { KnownHostPolicy::Reject };
};

struct ExecOptions
{
    std::string command;
    std::map<std::string, std::string> env;
    uint64_t timeout_ms { 0 };
};

struct SftpTransferOptions
{
    std::string local_path;
    std::string remote_path;
    uint64_t timeout_ms { 0 };
};

struct ShellOptions
{
    bool request_pty { false };
    std::string term;
    uint32_t cols { 80 };
    uint32_t rows { 24 };
    uint64_t timeout_ms { 0 };
};

struct TunnelOptions
{
    std::string local_host;
    uint16_t local_port { 0 };
    std::string remote_host;
    uint16_t remote_port { 0 };
    uint64_t timeout_ms { 0 };
};

struct Event
{
    EventKind kind { EventKind::OperationStarted };
    OperationId operation_id { 0 };
    SessionId session_id { 0 };
    ChannelId channel_id { 0 };
    TunnelId tunnel_id { 0 };
    std::map<std::string, std::string> fields;
    ErrorCode error_code { ErrorCode::None };
    std::string message;
};

std::string error_code_to_string(ErrorCode code);
std::string event_kind_to_string(EventKind kind);
std::map<std::string, std::string> redact_secret_fields(const std::map<std::string, std::string>& fields);

}
