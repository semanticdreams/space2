#include <array>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
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

bool write_text_file(const fs::path& path, const std::string& content)
{
    std::error_code ec;
    fs::create_directories(path.parent_path(), ec);
    if (ec) {
        std::cerr << "FAIL: create directories for " << path << ": " << ec.message() << "\n";
        return false;
    }
    std::ofstream out(path);
    if (!out) {
        std::cerr << "FAIL: open " << path << " for writing\n";
        return false;
    }
    out << content;
    if (!out) {
        std::cerr << "FAIL: write " << path << "\n";
        return false;
    }
    return true;
}

bool test_arbitrary_cwd_can_use_executable_relative_assets(const fs::path& executable)
{
    const fs::path unrelatedCwd = fs::temp_directory_path() / "space_runtime_asset_discovery_cwd";
    const fs::path xdgHome = fs::temp_directory_path() / "space_runtime_asset_discovery_xdg";
    fs::create_directories(unrelatedCwd);
    fs::create_directories(xdgHome);

    if (!unset_env_var("SPACE_ASSETS_PATH") ||
        !set_env_var("SPACE_DISABLE_AUDIO", "1") ||
        !set_env_var("XDG_DATA_HOME", xdgHome.string())) {
        std::cerr << "FAIL: failed to configure test environment\n";
        return false;
    }

    std::string command =
        "cd " + shell_quote(unrelatedCwd.string()) + " && " +
        shell_quote(executable.string()) + " --no-dotenv -c " +
        shell_quote("(print (+ 5 3))");

    std::string output;
    int exitCode = 1;
    if (!check(run_command_capture(command, output, exitCode), "run arbitrary-CWD command")) {
        return false;
    }
    if (!check(exitCode == 0, "arbitrary-CWD command should exit 0")) {
        std::cerr << output << "\n";
        return false;
    }
    if (!check(output.find("8") != std::string::npos, "Fennel command should print 8")) {
        std::cerr << output << "\n";
        return false;
    }
    return true;
}

bool test_project_cwd_main_overlays_executable_assets(const fs::path& executable)
{
    const fs::path projectCwd = fs::temp_directory_path() / "space_runtime_project_overlay";
    const fs::path xdgHome = fs::temp_directory_path() / "space_runtime_project_overlay_xdg";
    fs::remove_all(projectCwd);
    fs::remove_all(xdgHome);
    if (!write_text_file(projectCwd / "assets" / "lua" / "main.fnl",
                         "(print \"space-runtime-project-main-overlay\")\n")) {
        return false;
    }
    fs::create_directories(xdgHome);

    if (!unset_env_var("SPACE_ASSETS_PATH") ||
        !set_env_var("SPACE_DISABLE_AUDIO", "1") ||
        !set_env_var("XDG_DATA_HOME", xdgHome.string())) {
        std::cerr << "FAIL: failed to configure project overlay test environment\n";
        return false;
    }

    std::string command =
        "cd " + shell_quote(projectCwd.string()) + " && " +
        shell_quote(executable.string()) + " --no-dotenv -m main";

    std::string output;
    int exitCode = 1;
    if (!check(run_command_capture(command, output, exitCode), "run project cwd main overlay command")) {
        return false;
    }
    if (!check(exitCode == 0, "project cwd main overlay command should exit 0")) {
        std::cerr << output << "\n";
        return false;
    }
    if (!check(output.find("space-runtime-project-main-overlay") != std::string::npos,
               "project cwd assets/lua/main.fnl should be loaded")) {
        std::cerr << output << "\n";
        return false;
    }
    return true;
}

} // namespace

int main()
{
#if defined(_WIN32)
    const fs::path executable = fs::current_path() / "space.exe";
#else
    const fs::path executable = fs::current_path() / "space";
#endif
    if (!check(fs::exists(executable), "space executable should exist at " + executable.string())) {
        return 1;
    }
    if (!check(fs::exists(fs::current_path() / "assets" / "lua"),
               "build assets/lua should exist next to space executable")) {
        return 1;
    }
    if (!test_arbitrary_cwd_can_use_executable_relative_assets(executable)) {
        return 1;
    }
    if (!test_project_cwd_main_overlays_executable_assets(executable)) {
        return 1;
    }
    return 0;
}
