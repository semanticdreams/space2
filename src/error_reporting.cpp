#include "error_reporting.h"

#include <atomic>
#include <cstdlib>
#include <exception>
#include <filesystem>
#include <mutex>
#include <sstream>
#include <string>

#if defined(__linux__)
#include <unistd.h>
#endif

#include <sentry.h>

namespace {
std::mutex g_mutex;
bool g_enabled = false;
std::string g_dsn;
std::terminate_handler g_previous_terminate = nullptr;
std::atomic<bool> g_terminate_installed { false };

void set_error(std::string* out, const std::string& message)
{
    if (out) {
        *out = message;
    }
}

sentry_level_t to_sentry_level(error_reporting::Level level)
{
    switch (level) {
    case error_reporting::Level::Fatal: return SENTRY_LEVEL_FATAL;
    case error_reporting::Level::Error: return SENTRY_LEVEL_ERROR;
    case error_reporting::Level::Warning: return SENTRY_LEVEL_WARNING;
    case error_reporting::Level::Info: return SENTRY_LEVEL_INFO;
    case error_reporting::Level::Debug: return SENTRY_LEVEL_DEBUG;
    }
    return SENTRY_LEVEL_ERROR;
}

std::string executable_directory_crashpad_handler()
{
#if defined(__linux__)
    std::string buffer(4096, '\0');
    const ssize_t size = readlink("/proc/self/exe", buffer.data(), buffer.size() - 1);
    if (size <= 0) {
        return "crashpad_handler";
    }
    buffer.resize(static_cast<std::size_t>(size));
    return (std::filesystem::path(buffer).parent_path() / "crashpad_handler").string();
#else
    return "crashpad_handler";
#endif
}

bool is_valid_dsn(const std::string& dsn)
{
    const std::string http_scheme = "http://";
    const std::string https_scheme = "https://";
    const bool has_http_scheme = dsn.rfind(http_scheme, 0) == 0;
    const bool has_https_scheme = dsn.rfind(https_scheme, 0) == 0;
    if (!has_http_scheme && !has_https_scheme) {
        return false;
    }

    const std::size_t scheme_end = dsn.find("://");
    const std::size_t authority_start = scheme_end + 3;
    const std::size_t at = dsn.find('@', authority_start);
    if (at == std::string::npos || at == authority_start) {
        return false;
    }

    const std::size_t path_start = dsn.find('/', at + 1);
    return path_start != std::string::npos && path_start > at + 1 && path_start + 1 < dsn.size();
}

std::string current_exception_message()
{
    std::exception_ptr exception = std::current_exception();
    if (!exception) {
        return "std::terminate called without active exception";
    }

    try {
        std::rethrow_exception(exception);
    } catch (const std::exception& ex) {
        return ex.what();
    } catch (...) {
        return "std::terminate called with non-std exception";
    }
}

void terminate_handler()
{
    error_reporting::capture_exception("NativeTerminate", current_exception_message(), "std::terminate");
    error_reporting::flush(2000);
    if (g_previous_terminate) {
        g_previous_terminate();
    }
    std::abort();
}
}

namespace error_reporting {

bool init(const InitOptions& options, std::string* error_message)
{
    if (options.dsn.empty()) {
        set_error(error_message, "error reporting DSN is required");
        return false;
    }
    if (!is_valid_dsn(options.dsn)) {
        set_error(error_message, "error reporting DSN is invalid");
        return false;
    }

    std::lock_guard<std::mutex> lock(g_mutex);
    if (g_enabled) {
        if (g_dsn == options.dsn) {
            set_error(error_message, "");
            return true;
        }
        set_error(error_message, "error reporting is already initialized with a different DSN");
        return false;
    }

    sentry_options_t* sentry_options = sentry_options_new();
    if (!sentry_options) {
        set_error(error_message, "failed to allocate Sentry options");
        return false;
    }

    sentry_options_set_dsn(sentry_options, options.dsn.c_str());
    sentry_options_set_debug(sentry_options, options.debug ? 1 : 0);
    if (!options.release.empty()) {
        sentry_options_set_release(sentry_options, options.release.c_str());
    }
    if (!options.environment.empty()) {
        sentry_options_set_environment(sentry_options, options.environment.c_str());
    }
    if (!options.database_path.empty()) {
        sentry_options_set_database_path(sentry_options, options.database_path.c_str());
    }
    const std::string handler_path = executable_directory_crashpad_handler();
    sentry_options_set_handler_path(sentry_options, handler_path.c_str());

    const int init_result = sentry_init(sentry_options);
    if (init_result != 0) {
        std::ostringstream message;
        message << "Sentry initialization failed with status " << init_result;
        set_error(error_message, message.str());
        return false;
    }

    g_enabled = true;
    g_dsn = options.dsn;
    set_error(error_message, "");
    return true;
}

bool is_enabled()
{
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_enabled;
}

bool capture_message(Level level, const std::string& logger, const std::string& message)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_enabled) {
        return false;
    }
    sentry_capture_event(sentry_value_new_message_event(to_sentry_level(level), logger.c_str(), message.c_str()));
    return true;
}

bool capture_exception(const std::string& type,
                       const std::string& value,
                       const std::string& stacktrace,
                       const std::vector<std::pair<std::string, std::string>>& tags)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_enabled) {
        return false;
    }

    sentry_value_t event = sentry_value_new_event();
    sentry_event_set_level(event, SENTRY_LEVEL_ERROR);
    sentry_event_add_exception(event, sentry_value_new_exception(type.c_str(), value.c_str()));

    sentry_value_t extra = sentry_value_new_object();
    sentry_value_set_by_key(extra, "stacktrace", sentry_value_new_string(stacktrace.c_str()));
    sentry_value_set_by_key(event, "extra", extra);

    if (!tags.empty()) {
        sentry_value_t sentry_tags = sentry_value_new_object();
        for (const auto& tag : tags) {
            sentry_value_set_by_key(sentry_tags, tag.first.c_str(), sentry_value_new_string(tag.second.c_str()));
        }
        sentry_value_set_by_key(event, "tags", sentry_tags);
    }

    sentry_capture_event(event);
    return true;
}

bool flush(int timeout_ms)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_enabled) {
        return false;
    }
    return sentry_flush(static_cast<uint64_t>(timeout_ms)) == 0;
}

void shutdown()
{
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_enabled) {
        return;
    }
    sentry_close();
    g_enabled = false;
    g_dsn.clear();
}

void install_terminate_handler()
{
    bool expected = false;
    if (!g_terminate_installed.compare_exchange_strong(expected, true)) {
        return;
    }
    g_previous_terminate = std::set_terminate(terminate_handler);
}

} // namespace error_reporting
