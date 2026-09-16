#include <array>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>

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

bool unset_env_var(const std::string& key)
{
#if defined(_WIN32)
    return _putenv_s(key.c_str(), "") == 0;
#else
    return unsetenv(key.c_str()) == 0;
#endif
}

std::string shell_quote(const std::string& value)
{
#if defined(_WIN32)
    std::string quoted = "\"";
    for (char c : value) {
        if (c == '"') {
            quoted += "\\\"";
        } else {
            quoted.push_back(c);
        }
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

bool run_command_capture(const std::string& command, std::string& output, int& exitCode)
{
    std::array<char, 256> buffer {};
    std::string fullCommand = command + " 2>&1";
#if defined(_WIN32)
    FILE* pipe = _popen(fullCommand.c_str(), "r");
#else
    FILE* pipe = popen(fullCommand.c_str(), "r");
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
    exitCode = status;
    return status != -1;
#else
    int status = pclose(pipe);
    if (status == -1) {
        return false;
    }
    exitCode = WIFEXITED(status) ? WEXITSTATUS(status) : 128;
    return true;
#endif
}

bool check(bool condition, const std::string& message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        return false;
    }
    return true;
}

} // namespace

int main()
{
#if defined(_WIN32)
    const fs::path executable = fs::current_path() / "space-cli.exe";
#else
    const fs::path executable = fs::current_path() / "space";
#endif
    const fs::path unrelatedCwd = fs::temp_directory_path() / "space_runtime_asset_discovery_cwd";
    const fs::path xdgHome = fs::temp_directory_path() / "space_runtime_asset_discovery_xdg";
    fs::create_directories(unrelatedCwd);
    fs::create_directories(xdgHome);

    if (!check(fs::exists(executable), "space executable should exist at " + executable.string())) {
        return 1;
    }
    if (!check(fs::exists(fs::current_path() / "assets" / "lua"),
               "build assets/lua should exist next to space executable")) {
        return 1;
    }
    if (!unset_env_var("SPACE_ASSETS_PATH") ||
        !set_env_var("SPACE_DISABLE_AUDIO", "1") ||
        !set_env_var("XDG_DATA_HOME", xdgHome.string())) {
        std::cerr << "FAIL: failed to configure test environment\n";
        return 1;
    }

    std::string command =
        "cd " + shell_quote(unrelatedCwd.string()) + " && " +
        shell_quote(executable.string()) + " --no-dotenv -c " +
        shell_quote("(print (+ 5 3))");

    std::string output;
    int exitCode = 1;
    if (!check(run_command_capture(command, output, exitCode), "run arbitrary-CWD command")) {
        return 1;
    }
    if (!check(exitCode == 0, "arbitrary-CWD command should exit 0")) {
        std::cerr << output << "\n";
        return 1;
    }
    if (!check(output.find("8") != std::string::npos, "Fennel command should print 8")) {
        std::cerr << output << "\n";
        return 1;
    }
    return 0;
}
