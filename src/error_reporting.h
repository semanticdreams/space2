#pragma once

#include <string>
#include <utility>
#include <vector>

namespace error_reporting {

enum class Level { Fatal, Error, Warning, Info, Debug };

struct InitOptions {
    std::string dsn;
    std::string environment;
    std::string release;
    std::string database_path;
    bool debug { false };
};

bool init(const InitOptions& options, std::string* error_message = nullptr);
bool is_enabled();
bool capture_message(Level level, const std::string& logger, const std::string& message);
bool capture_exception(const std::string& type,
                       const std::string& value,
                       const std::string& stacktrace,
                       const std::vector<std::pair<std::string, std::string>>& tags = {});
bool flush(int timeout_ms);
void shutdown();
void install_terminate_handler();

} // namespace error_reporting
