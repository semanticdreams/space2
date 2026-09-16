#include "httplib.h"

#include <array>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#if !defined(_WIN32)
#include <sys/wait.h>
#endif

namespace fs = std::filesystem;

namespace {

bool set_env_var(const std::string& key, const std::string& value)
{
#if defined(_WIN32)
    return _putenv_s(key.c_str(), value.c_str()) == 0;
#else
    return setenv(key.c_str(), value.c_str(), 1) == 0;
#endif
}

std::string shell_quote(const std::string& value)
{
#if defined(_WIN32)
    std::string quoted = "\"";
    size_t backslash_count = 0;
    for (char c : value) {
        if (c == '\\') {
            backslash_count++;
            continue;
        }
        if (c == '"') {
            quoted.append(backslash_count * 2 + 1, '\\');
            quoted.push_back('"');
            backslash_count = 0;
            continue;
        }
        if (backslash_count > 0) {
            quoted.append(backslash_count, '\\');
            backslash_count = 0;
        }
        quoted.push_back(c);
    }
    if (backslash_count > 0) {
        quoted.append(backslash_count * 2, '\\');
    }
    quoted.push_back('"');
    return quoted;
#else
    std::string quoted = "'";
    for (char c : value) {
        if (c == '\'') {
            quoted += "'\\''";
        } else {
            quoted.push_back(c);
        }
    }
    quoted.push_back('\'');
    return quoted;
#endif
}

bool run_command_capture(const std::string& command, std::string& output, int& exit_code)
{
    std::array<char, 256> buffer {};
    std::string full_command = command + " 2>&1";
#if defined(_WIN32)
    FILE* pipe = _popen(full_command.c_str(), "r");
#else
    FILE* pipe = popen(full_command.c_str(), "r");
#endif
    if (!pipe) {
        return false;
    }

    output.clear();
    while (fgets(buffer.data(), static_cast<int>(buffer.size()), pipe) != nullptr) {
        output.append(buffer.data());
    }

#if defined(_WIN32)
    int status = _pclose(pipe);
    if (status == -1) {
        return false;
    }
    exit_code = status;
#else
    int status = pclose(pipe);
    if (status == -1) {
        return false;
    }
    if (WIFEXITED(status)) {
        exit_code = WEXITSTATUS(status);
    } else {
        exit_code = 128;
    }
#endif
    return true;
}

std::string build_command(const fs::path& executable, const std::vector<std::string>& args)
{
    std::string command = shell_quote(executable.string());
    for (const std::string& arg : args) {
        command += " " + shell_quote(arg);
    }
    return command;
}

bool check(bool condition, const std::string& message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        return false;
    }
    return true;
}

struct LocalEnvelopeServer {
    httplib::Server server;
    std::thread thread;
    std::mutex mutex;
    std::vector<std::string> bodies;
    int port { 0 };

    bool start()
    {
        server.Post(R"(.*)", [&](const httplib::Request& req, httplib::Response& res) {
            std::lock_guard<std::mutex> lock(mutex);
            bodies.push_back(req.body);
            res.status = 200;
            res.set_content("{}", "application/json");
        });

        port = server.bind_to_any_port("127.0.0.1");
        if (port <= 0) {
            return false;
        }
        thread = std::thread([this]() { server.listen_after_bind(); });
        return true;
    }

    void stop()
    {
        server.stop();
        if (thread.joinable()) {
            thread.join();
        }
    }

    bool contains(const std::string& needle)
    {
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
        while (std::chrono::steady_clock::now() < deadline) {
            {
                std::lock_guard<std::mutex> lock(mutex);
                for (const std::string& body : bodies) {
                    if (body.find(needle) != std::string::npos) {
                        return true;
                    }
                }
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }
        return false;
    }

    std::string dsn() const
    {
        return "http://public@127.0.0.1:" + std::to_string(port) + "/1";
    }
};

} // namespace

int main()
{
    const fs::path assets_dir = fs::current_path().parent_path() / "assets";
    const fs::path fennel_file_error = assets_dir / "lua" / "tests" / "file-error.fnl";
    const fs::path lua_file_error = assets_dir / "lua" / "tests" / "lua-file-error.lua";
#if defined(_WIN32)
    const fs::path executable = fs::current_path() / "space.exe";
#else
    const fs::path executable = fs::current_path() / "space";
#endif

    if (!set_env_var("SPACE_ASSETS_PATH", assets_dir.string())) {
        std::cerr << "FAIL: failed to set SPACE_ASSETS_PATH\n";
        return 1;
    }
    if (!set_env_var("SPACE_DISABLE_AUDIO", "1")) {
        std::cerr << "FAIL: failed to set SPACE_DISABLE_AUDIO\n";
        return 1;
    }

    struct FailureCase {
        std::string name;
        std::vector<std::string> args;
        std::string expected_error;
    };

    const std::vector<FailureCase> cases = {
        {
            "module startup",
            {"-m", "tests.module-error"},
            "tests.module-error startup failure",
        },
        {
            "module function",
            {"-m", "tests.module-function-error:explode"},
            "tests.module-function-error function failure",
        },
        {
            "command",
            {"-c", "(error \"tests.command-error failure\")"},
            "tests.command-error failure",
        },
        {
            "fennel file",
            {fennel_file_error.string()},
            "tests.file-error file failure",
        },
        {
            "lua file",
            {lua_file_error.string()},
            "tests.lua-file-error file failure",
        },
    };

    for (const FailureCase& failure_case : cases) {
        std::string output;
        int exit_code = 0;
        if (!check(run_command_capture(build_command(executable, failure_case.args), output, exit_code),
                   "run " + failure_case.name + " command")) {
            return 1;
        }
        if (!check(exit_code != 0, failure_case.name + " command should fail")) {
            std::cerr << output << "\n";
            return 1;
        }
        if (!check(output.find(failure_case.expected_error) != std::string::npos,
                   failure_case.name + " error should be reported")) {
            std::cerr << output << "\n";
            return 1;
        }
    }

    LocalEnvelopeServer server;
    if (!check(server.start(), "start local error reporting server")) {
        return 1;
    }

    const fs::path reporting_db = fs::temp_directory_path() / "space-error-reporting-test-db";
    if (!check(set_env_var("SPACE_TEST_ERROR_REPORTING_DSN", server.dsn()),
               "set SPACE_TEST_ERROR_REPORTING_DSN")) {
        server.stop();
        return 1;
    }
    if (!check(set_env_var("SPACE_TEST_ERROR_REPORTING_DB", reporting_db.string()),
               "set SPACE_TEST_ERROR_REPORTING_DB")) {
        server.stop();
        return 1;
    }

    std::string startup_output;
    int startup_exit_code = 0;
    if (!check(run_command_capture(build_command(executable, {"-m", "tests.error-reporting-startup-error:main"}),
                                   startup_output,
                                   startup_exit_code),
               "run error reporting startup fixture")) {
        server.stop();
        return 1;
    }
    if (!check(startup_exit_code != 0, "error reporting startup fixture should fail")) {
        std::cerr << startup_output << "\n";
        server.stop();
        return 1;
    }
    if (!check(startup_output.find("tests.error-reporting startup failure") != std::string::npos,
               "startup fixture preserves reported error output")) {
        std::cerr << startup_output << "\n";
        server.stop();
        return 1;
    }
    if (!check(server.contains("tests.error-reporting startup failure"),
               "startup fixture delivered local error report")) {
        server.stop();
        return 1;
    }

    std::string callback_output;
    int callback_exit_code = 0;
    if (!check(run_command_capture(build_command(executable, {"-m", "tests.error-reporting-callback-error:main"}),
                                   callback_output,
                                   callback_exit_code),
               "run error reporting callback fixture")) {
        server.stop();
        return 1;
    }
    if (!check(callback_exit_code == 0, "error reporting callback fixture should succeed")) {
        std::cerr << callback_output << "\n";
        server.stop();
        return 1;
    }
    if (!check(callback_output.find("[callbacks] invocation failed") != std::string::npos,
               "callback fixture preserves callback failure output")) {
        std::cerr << callback_output << "\n";
        server.stop();
        return 1;
    }
    if (!check(server.contains("tests.error-reporting callback failure"),
               "callback fixture delivered local error report")) {
        server.stop();
        return 1;
    }

    server.stop();

    return 0;
}
