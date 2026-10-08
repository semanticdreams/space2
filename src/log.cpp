#include "log.h"

#include <atomic>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <mutex>
#include <thread>
#include <unordered_map>

#include <spdlog/async.h>
#include <spdlog/fmt/fmt.h>
#include <spdlog/spdlog.h>
#include <spdlog/sinks/rotating_file_sink.h>
#include <spdlog/sinks/basic_file_sink.h>
#include <spdlog/sinks/stdout_color_sinks.h>

namespace {

std::mutex log_mutex;
std::mutex log_levels_mutex;
std::shared_ptr<spdlog::logger> async_logger;
std::vector<spdlog::sink_ptr> log_sinks;
spdlog::sink_ptr log_file_sink;
bool log_ready = false;
std::atomic<bool> log_shutdown_started { false };
std::atomic<const std::atomic<uint64_t>*> frame_id_provider { nullptr };
std::string log_output_path = std::string(GL_LOG_FILE);
std::unordered_map<std::string, LogLevel> configured_logger_levels;

spdlog::level::level_enum to_spd_level(LogLevel level)
{
    switch (level) {
        case Debug:
            return spdlog::level::debug;
        case Info:
            return spdlog::level::info;
        case Warning:
            return spdlog::level::warn;
        case Error:
            return spdlog::level::err;
    }
    return spdlog::level::info;
}

bool log_lifecycle_debug_enabled()
{
    // Enable high-volume log init diagnostics with SPACE_LOG_LIFECYCLE_DEBUG=1.
    static const bool enabled = []() {
        const char* value = std::getenv("SPACE_LOG_LIFECYCLE_DEBUG");
        return value && value[0] != '\0' && value[0] != '0';
    }();
    return enabled;
}

bool native_lifecycle_diagnostics_enabled()
{
    // Sparse native lifecycle diagnostics are on by default for spontaneous crash evidence.
    // Disable with SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS=0 when stderr noise is not acceptable.
    static const bool enabled = []() {
        const char* value = std::getenv("SPACE_NATIVE_LIFECYCLE_DIAGNOSTICS");
        return !(value && value[0] == '0' && value[1] == '\0');
    }();
    return enabled;
}

unsigned long long diagnostic_thread_id()
{
    return static_cast<unsigned long long>(std::hash<std::thread::id> {}(std::this_thread::get_id()));
}

void log_lifecycle_diag(const char* event, const char* logger_name = nullptr, bool always_on = false)
{
    if (!(always_on ? native_lifecycle_diagnostics_enabled() : log_lifecycle_debug_enabled())) {
        return;
    }
    std::fprintf(stderr,
                 "space-log-lifecycle event=%s thread=%llu logger=%s shutdown_started=%d ready=%d\n",
                 event,
                 diagnostic_thread_id(),
                 logger_name ? logger_name : "-",
                 log_shutdown_started.load(std::memory_order_relaxed) ? 1 : 0,
                 log_ready ? 1 : 0);
    std::fflush(stderr);
}

LogLevel from_spd_level(spdlog::level::level_enum level)
{
    switch (level) {
        case spdlog::level::trace:
        case spdlog::level::debug:
            return Debug;
        case spdlog::level::info:
            return Info;
        case spdlog::level::warn:
            return Warning;
        case spdlog::level::err:
        case spdlog::level::critical:
        case spdlog::level::off:
            return Error;
        default:
            return Info;
    }
}

void ensure_logger()
{
    if (log_shutdown_started.load(std::memory_order_relaxed)) {
        log_lifecycle_diag("ensure-after-shutdown-begin", nullptr, true);
    }
    if (!log_ready) {
        LogConfig config;
        log_init(config);
    }
}

std::string escape_value(const std::string& value)
{
    std::string escaped;
    escaped.reserve(value.size());
    for (char ch : value) {
        if (ch == '\\' || ch == '"') {
            escaped.push_back('\\');
            escaped.push_back(ch);
        } else if (ch == '\n') {
            escaped.append("\\n");
        } else if (ch == '\r') {
            escaped.append("\\r");
        } else if (ch == '\t') {
            escaped.append("\\t");
        } else {
            escaped.push_back(ch);
        }
    }
    return escaped;
}

bool needs_quotes(const std::string& value)
{
    for (char ch : value) {
        if (std::isspace(static_cast<unsigned char>(ch)) || ch == '"' || ch == '\\') {
            return true;
        }
    }
    return value.empty();
}

std::string format_kv(const std::string& key, const std::string& value, bool quote)
{
    std::string out = key;
    out.push_back('=');
    if (quote || needs_quotes(value)) {
        out.push_back('"');
        out.append(escape_value(value));
        out.push_back('"');
    } else {
        out.append(value);
    }
    return out;
}

std::string build_payload(const std::string& fields, const std::string& message)
{
    if (fields.empty()) {
        return message;
    }
    std::string payload = fields;
    payload.push_back('\n');
    payload.append(message);
    return payload;
}

struct PayloadParts {
    std::string_view fields;
    std::string_view message;
};

std::string_view extract_fields(std::string_view payload, std::string_view& out_message)
{
    std::size_t sep = payload.find('\n');
    if (sep == std::string_view::npos) {
        out_message = payload;
        return {};
    }
    out_message = payload.substr(sep + 1);
    return payload.substr(0, sep);
}

PayloadParts split_payload(const spdlog::details::log_msg& msg)
{
    std::string_view payload_view(msg.payload.data(), msg.payload.size());
    std::string_view message_view;
    std::string_view fields_view = extract_fields(payload_view, message_view);
    return { fields_view, message_view };
}

void append_prefix_and_fields(const spdlog::details::log_msg& msg,
                              spdlog::memory_buf_t& dest,
                              std::string_view fields_view)
{
    using namespace std::chrono;
    const auto time = msg.time;
    const auto tt = spdlog::log_clock::to_time_t(time);
    std::tm tm = spdlog::details::os::gmtime(tt);
    auto ms = duration_cast<milliseconds>(time.time_since_epoch()) % 1000;

    fmt::format_to(std::back_inserter(dest),
                   "ts={:04d}-{:02d}-{:02d}T{:02d}:{:02d}:{:02d}.{:03d}Z ",
                   tm.tm_year + 1900,
                   tm.tm_mon + 1,
                   tm.tm_mday,
                   tm.tm_hour,
                   tm.tm_min,
                   tm.tm_sec,
                   static_cast<int>(ms.count()));

    auto level_view = spdlog::level::to_string_view(msg.level);
    std::string level(level_view.data(), level_view.size());
    for (char& ch : level) {
        ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    }
    fmt::format_to(std::back_inserter(dest),
                   "level={} logger={} thread={} ",
                   level,
                   msg.logger_name,
                   msg.thread_id);

    const auto* provider = frame_id_provider.load(std::memory_order_relaxed);
    if (provider) {
        uint64_t value = provider->load(std::memory_order_relaxed);
        fmt::format_to(std::back_inserter(dest), "frame={} ", value);
    } else {
        fmt::format_to(std::back_inserter(dest), "frame=- ");
    }

    if (!fields_view.empty()) {
        fmt::format_to(std::back_inserter(dest), "{} ", fields_view);
    }
}

class KeyValueFormatter : public spdlog::formatter {
public:
    void format(const spdlog::details::log_msg& msg, spdlog::memory_buf_t& dest) override
    {
        PayloadParts parts = split_payload(msg);
        append_prefix_and_fields(msg, dest, parts.fields);

        std::string message(parts.message);
        fmt::format_to(std::back_inserter(dest), "msg=\"{}\"\n", escape_value(message));
    }

    std::unique_ptr<spdlog::formatter> clone() const override
    {
        return spdlog::details::make_unique<KeyValueFormatter>();
    }
};

class ColorKeyValueFormatter : public spdlog::formatter {
public:
    void format(const spdlog::details::log_msg& msg, spdlog::memory_buf_t& dest) override
    {
        PayloadParts parts = split_payload(msg);
        append_prefix_and_fields(msg, dest, parts.fields);

        fmt::format_to(std::back_inserter(dest), "msg=\"");
        size_t color_start = dest.size();

        std::string message(parts.message);
        fmt::format_to(std::back_inserter(dest), "{}", escape_value(message));
        size_t color_end = dest.size();

        fmt::format_to(std::back_inserter(dest), "\"\n");

        auto& mutable_msg = const_cast<spdlog::details::log_msg&>(msg);
        mutable_msg.color_range_start = color_start;
        mutable_msg.color_range_end = color_end;
    }

    std::unique_ptr<spdlog::formatter> clone() const override
    {
        return spdlog::details::make_unique<ColorKeyValueFormatter>();
    }
};

} // namespace

std::shared_ptr<spdlog::logger> log_get_logger(const std::string& name)
{
    if (log_shutdown_started.load(std::memory_order_relaxed)) {
        log_lifecycle_diag("get-logger-after-shutdown-begin", name.c_str(), true);
    }
    ensure_logger();

    if (auto existing = spdlog::get(name)) {
        return existing;
    }

    auto logger = std::make_shared<spdlog::async_logger>(
        name,
        log_sinks.begin(),
        log_sinks.end(),
        spdlog::thread_pool(),
        spdlog::async_overflow_policy::block
    );
    logger->set_level(to_spd_level(LOG_CONFIG.reporting_level));
    logger->flush_on(spdlog::level::warn);
    spdlog::register_logger(logger);
    return logger;
}

void log_init(const LogConfig& config)
{
    std::lock_guard<std::mutex> lock(log_mutex);
    log_lifecycle_diag("init-begin");
    spdlog::shutdown();
    log_shutdown_started.store(false, std::memory_order_relaxed);

    std::string selected_output_path = config.output_path.empty()
        ? log_output_path
        : config.output_path;
    if (selected_output_path.empty()) {
        selected_output_path = std::string(GL_LOG_FILE);
    }
    log_output_path = selected_output_path;

    auto stdout_sink = std::make_shared<spdlog::sinks::stdout_color_sink_mt>();
    stdout_sink->set_formatter(std::make_unique<ColorKeyValueFormatter>());
    auto file_sink = std::make_shared<spdlog::sinks::rotating_file_sink_mt>(
        log_output_path,
        5 * 1024 * 1024,
        3
    );
    file_sink->set_formatter(std::make_unique<KeyValueFormatter>());
    log_sinks.clear();
    log_sinks.push_back(stdout_sink);
    log_sinks.push_back(file_sink);
    log_file_sink = file_sink;

    spdlog::init_thread_pool(8192, 1);
    LOG_CONFIG.reporting_level = config.reporting_level;
    LOG_CONFIG.restart = config.restart;
    LOG_CONFIG.output_path = log_output_path;
    log_ready = true;

    static const std::vector<std::string> default_loggers = {
        "space",
        "engine",
        "window",
        "shader",
        "resources",
        "opengl",
        "audio",
        "physics",
        "lua",
        "jobs",
        "http",
        "input",
        "render",
        "terminal"
    };

    for (const auto& name : default_loggers) {
        auto logger = log_get_logger(name);
        logger->set_level(to_spd_level(config.reporting_level));
    }
    {
        std::lock_guard<std::mutex> level_lock(log_levels_mutex);
        configured_logger_levels.clear();
        for (const auto& name : default_loggers) {
            configured_logger_levels[name] = config.reporting_level;
        }
    }
    log_set_level_for("shader", Warning);

    async_logger = log_get_logger("space");
    async_logger->flush_on(spdlog::level::warn);
    spdlog::set_default_logger(async_logger);
    log_lifecycle_diag("init-end");
}

void log_shutdown()
{
    std::lock_guard<std::mutex> lock(log_mutex);
    log_shutdown_started.store(true, std::memory_order_relaxed);
    log_lifecycle_diag("shutdown-begin", nullptr, true);
    spdlog::shutdown();
    async_logger.reset();
    log_sinks.clear();
    log_file_sink.reset();
    log_ready = false;
    log_lifecycle_diag("shutdown-end", nullptr, true);
}

void log_set_level(LogLevel level)
{
    LOG_CONFIG.reporting_level = level;
    log_set_level_for("space", level);
}

void log_set_level_for(const std::string& name, LogLevel level)
{
    auto logger = log_get_logger(name);
    logger->set_level(to_spd_level(level));
    std::lock_guard<std::mutex> lock(log_levels_mutex);
    configured_logger_levels[name] = level;
}

LogLevel log_get_level_for(const std::string& name)
{
    ensure_logger();
    if (auto logger = spdlog::get(name)) {
        return from_spd_level(logger->level());
    }
    {
        std::lock_guard<std::mutex> lock(log_levels_mutex);
        auto found = configured_logger_levels.find(name);
        if (found != configured_logger_levels.end()) {
            return found->second;
        }
    }
    return LOG_CONFIG.reporting_level;
}

bool log_should_log(const std::string& name, LogLevel level)
{
    auto logger = log_get_logger(name);
    return logger->should_log(to_spd_level(level));
}

void log_write(LogLevel level, const std::string& message)
{
    log_write_named_fields("space", level, "", message);
}

void log_write_named(const std::string& name, LogLevel level, const std::string& message)
{
    log_write_named_fields(name, level, "", message);
}

void log_write_named_fields(const std::string& name, LogLevel level, const std::string& fields, const std::string& message)
{
    auto logger = log_get_logger(name);
    logger->log(to_spd_level(level), build_payload(fields, message));
}

void log_write_file_only(const std::string& name, LogLevel level, const std::string& message)
{
    try {
        spdlog::sink_ptr file_sink;
        {
            std::lock_guard<std::mutex> lock(log_mutex);
            if (!log_ready || !log_file_sink) {
                return;
            }
            file_sink = log_file_sink;
        }

        spdlog::logger logger(name, file_sink);
        logger.set_level(spdlog::level::trace);
        std::string payload = message.find('\n') == std::string::npos ? message : "\n" + message;
        logger.log(to_spd_level(level), payload);
        logger.flush();
    }
    catch (...) {
        // Preserve the original stderr path even if crash-path logging fails.
    }
}

void log_flush()
{
    ensure_logger();
    spdlog::apply_all([](std::shared_ptr<spdlog::logger> logger) {
        logger->flush();
    });
}

void log_set_frame_id_provider(const std::atomic<uint64_t>* provider)
{
    frame_id_provider.store(provider, std::memory_order_relaxed);
}

void log_set_output_path(const std::string& path)
{
    LogConfig config = LOG_CONFIG;
    config.output_path = path.empty() ? std::string(GL_LOG_FILE) : path;
    config.restart = false;
    log_init(config);
}

std::string log_get_output_path()
{
    return log_output_path;
}

Log::Log(const std::string& logger_name)
    : name(logger_name)
{
}

Log::~Log()
{
    if (!enabled || (os.str().empty() && fields.empty())) {
        return;
    }
    std::string field_blob;
    for (const auto& field : fields) {
        if (!field_blob.empty()) {
            field_blob.push_back(' ');
        }
        field_blob.append(field);
    }
    log_write_named_fields(name, level, field_blob, os.str());
    os.str("");
    os.clear();
}

void Log::restart()
{
    LogConfig config = LOG_CONFIG;
    config.restart = true;
    log_init(config);
}

Log& Log::get(LogLevel new_level)
{
    level = new_level;
    enabled = log_should_log(name, new_level);
    return *this;
}

Log& Log::operator<<(const LogField& field)
{
    if (!enabled) {
        return *this;
    }
    fields.push_back(field.formatted);
    return *this;
}

LogField log_kv_string(const std::string& key, const std::string& value, bool quote_value)
{
    return { format_kv(key, value, quote_value) };
}

LogField log_kv(const std::string& key, const std::string& value)
{
    return log_kv_string(key, value, false);
}

LogField log_kv(const std::string& key, const char* value)
{
    return log_kv_string(key, value ? std::string(value) : std::string(), false);
}
