#include <array>
#include <chrono>
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

fs::path make_temp_root(const std::string& name)
{
    auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    fs::path root = fs::temp_directory_path() / (name + "_" + std::to_string(stamp));
    fs::create_directories(root);
    return root;
}

bool check(bool condition, const std::string& message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        return false;
    }
    return true;
}

fs::path space_executable()
{
#if defined(_WIN32)
    return fs::current_path() / "space-cli.exe";
#else
    return fs::current_path() / "space";
#endif
}

std::string logging_command(const fs::path& cwd, const fs::path& executable)
{
    return "cd " + shell_quote(cwd.string()) + " && " +
        shell_quote(executable.string()) + " --no-dotenv -c " +
        shell_quote("(do (local logging (require :logging)) (logging.info \"native logging integration\") (logging.flush))");
}

std::string logging_command_dotenv(const fs::path& cwd, const fs::path& executable,
                                   const std::string& dotenv_opts)
{
    return "cd " + shell_quote(cwd.string()) + " && " +
        shell_quote(executable.string()) + " " + dotenv_opts + " -c " +
        shell_quote("(do (local logging (require :logging)) (logging.info \"native logging integration\") (logging.flush))");
}

bool run_space_with_env(const fs::path& cwd, const fs::path& executable, std::string& output, int& exitCode)
{
    return run_command_capture(logging_command(cwd, executable), output, exitCode);
}

bool test_default_log_path()
{
    fs::path root = make_temp_root("space_native_log_default");
    fs::path cwd = root / "cwd";
    fs::path xdg = root / "xdg-cache";
    fs::create_directories(cwd);
    unset_env_var("SPACE_LOG_DIR");
    set_env_var("XDG_CACHE_HOME", xdg.string());
    set_env_var("SPACE_DISABLE_AUDIO", "1");

    std::string output;
    int exitCode = 1;
    if (!check(run_space_with_env(cwd, space_executable(), output, exitCode), "run default logging command")) {
        return false;
    }
    if (!check(exitCode == 0, "default logging command should exit 0")) {
        std::cerr << output << "\n";
        return false;
    }
    return check(fs::exists(xdg / "space" / "log" / "space.log"), "default log file should exist") &&
        check(!fs::exists(cwd / "gl.log"), "default run should not create cwd gl.log");
}

bool test_space_log_dir_override()
{
    fs::path root = make_temp_root("space_native_log_override");
    fs::path cwd = root / "cwd";
    fs::path logs = root / "custom-logs";
    fs::create_directories(cwd);
    set_env_var("SPACE_LOG_DIR", logs.string());
    set_env_var("XDG_CACHE_HOME", (root / "xdg-cache").string());
    set_env_var("SPACE_DISABLE_AUDIO", "1");

    std::string output;
    int exitCode = 1;
    if (!check(run_space_with_env(cwd, space_executable(), output, exitCode), "run override logging command")) {
        return false;
    }
    if (!check(exitCode == 0, "override logging command should exit 0")) {
        std::cerr << output << "\n";
        return false;
    }
    return check(fs::exists(logs / "space.log"), "SPACE_LOG_DIR log file should exist") &&
        check(!fs::exists(cwd / "gl.log"), "override run should not create cwd gl.log");
}

bool test_invalid_log_directory_fails_loudly()
{
    fs::path root = make_temp_root("space_native_log_invalid");
    fs::path cwd = root / "cwd";
    fs::path notADir = root / "not-a-dir";
    fs::create_directories(cwd);
    std::ofstream out(notADir);
    out << "not a directory\n";
    out.close();

    set_env_var("SPACE_LOG_DIR", (notADir / "child").string());
    set_env_var("XDG_CACHE_HOME", (root / "xdg-cache").string());
    set_env_var("SPACE_DISABLE_AUDIO", "1");

    std::string output;
    int exitCode = 0;
    if (!check(run_space_with_env(cwd, space_executable(), output, exitCode), "run invalid logging command")) {
        return false;
    }
    return check(exitCode != 0, "invalid logging command should fail") &&
        check(output.find("failed to initialize logging") != std::string::npos,
              "invalid logging command should print explicit startup error") &&
        check(!fs::exists(cwd / "gl.log"), "invalid run should not create cwd gl.log");
}

bool test_dotenv_spacelogdir()
{
    fs::path root = make_temp_root("space_native_dotenv_default");
    fs::path cwd = root / "cwd";
    fs::path logs = root / "dotenv-logs";
    fs::create_directories(cwd);
    fs::create_directories(logs);

    // Write a .env file supplying SPACE_LOG_DIR
    std::ofstream env_file(cwd / ".env");
    env_file << "SPACE_LOG_DIR=" << logs.string() << "\n";
    env_file.close();

    // No process-level SPACE_LOG_DIR — let .env provide it
    unset_env_var("SPACE_LOG_DIR");
    set_env_var("XDG_CACHE_HOME", (root / "xdg-cache").string());
    set_env_var("SPACE_DISABLE_AUDIO", "1");

    std::string output;
    int exitCode = 1;
    std::string cmd = logging_command_dotenv(cwd, space_executable(), "");
    if (!check(run_command_capture(cmd, output, exitCode), "run dotenv default logging command")) {
        return false;
    }
    if (!check(exitCode == 0, "dotenv default logging command should exit 0")) {
        std::cerr << output << "\n";
        return false;
    }
    return check(fs::exists(logs / "space.log"), ".env SPACE_LOG_DIR log file should exist") &&
        check(!fs::exists(cwd / "gl.log"), "dotenv run should not create cwd gl.log");
}

bool test_no_dotenv_skip()
{
    fs::path root = make_temp_root("space_native_no_dotenv");
    fs::path cwd = root / "cwd";
    fs::path logs = root / "dotenv-logs";
    fs::path xdg = root / "xdg-cache";
    fs::create_directories(cwd);
    fs::create_directories(logs);

    std::ofstream env_file(cwd / ".env");
    env_file << "SPACE_LOG_DIR=" << logs.string() << "\n";
    env_file.close();

    unset_env_var("SPACE_LOG_DIR");
    set_env_var("XDG_CACHE_HOME", xdg.string());
    set_env_var("SPACE_DISABLE_AUDIO", "1");

    std::string output;
    int exitCode = 1;
    std::string cmd = logging_command_dotenv(cwd, space_executable(), "--no-dotenv");
    if (!check(run_command_capture(cmd, output, exitCode), "run no-dotenv logging command")) {
        return false;
    }
    if (!check(exitCode == 0, "no-dotenv logging command should exit 0")) {
        std::cerr << output << "\n";
        return false;
    }
    // With --no-dotenv, .env is ignored — log goes to default XDG location
    return check(fs::exists(xdg / "space" / "log" / "space.log"),
                 "no-dotenv log file should exist in default XDG location") &&
        check(!fs::exists(logs / "space.log"),
              "no-dotenv run should NOT use .env SPACE_LOG_DIR") &&
        check(!fs::exists(cwd / "gl.log"), "no-dotenv run should not create cwd gl.log");
}

bool test_dotenv_custom_path()
{
    fs::path root = make_temp_root("space_native_dotenv_custom");
    fs::path cwd = root / "cwd";
    fs::path logs = root / "custom-dotenv-logs";
    fs::path dotenv_file = root / "custom.env";
    fs::create_directories(cwd);
    fs::create_directories(logs);

    std::ofstream env_file(dotenv_file);
    env_file << "SPACE_LOG_DIR=" << logs.string() << "\n";
    env_file.close();

    unset_env_var("SPACE_LOG_DIR");
    set_env_var("XDG_CACHE_HOME", (root / "xdg-cache").string());
    set_env_var("SPACE_DISABLE_AUDIO", "1");

    std::string output;
    int exitCode = 1;
    std::string cmd = logging_command_dotenv(cwd, space_executable(),
                                             "--dotenv " + shell_quote(dotenv_file.string()));
    if (!check(run_command_capture(cmd, output, exitCode), "run custom dotenv logging command")) {
        return false;
    }
    if (!check(exitCode == 0, "custom dotenv logging command should exit 0")) {
        std::cerr << output << "\n";
        return false;
    }
    return check(fs::exists(logs / "space.log"), "--dotenv <file> SPACE_LOG_DIR log file should exist") &&
        check(!fs::exists(cwd / "gl.log"), "custom dotenv run should not create cwd gl.log");
}

// --no-dotenv placed AFTER -c should be treated as a Fennel/script argument,
// not a global flag. The dotenv pre-scan must stop at -c boundaries.
bool test_no_dotenv_after_c_is_fennel_arg()
{
    fs::path root = make_temp_root("space_native_no_dotenv_after_c");
    fs::path cwd = root / "cwd";
    fs::path logs = root / "dotenv-logs";
    fs::path xdg = root / "xdg-cache";
    fs::create_directories(cwd);
    fs::create_directories(logs);

    std::ofstream env_file(cwd / ".env");
    env_file << "SPACE_LOG_DIR=" << logs.string() << "\n";
    env_file.close();

    unset_env_var("SPACE_LOG_DIR");
    set_env_var("XDG_CACHE_HOME", xdg.string());
    set_env_var("SPACE_DISABLE_AUDIO", "1");

    std::string output;
    int exitCode = 1;
    // --no-dotenv appears AFTER -c — it must be a Fennel arg, not a global flag
    std::string cmd = "cd " + shell_quote(cwd.string()) + " && " +
        shell_quote(space_executable().string()) + " -c " +
        shell_quote("(do (local logging (require :logging)) (logging.info \"native logging integration\") (logging.flush))") +
        " --no-dotenv";
    if (!check(run_command_capture(cmd, output, exitCode), "run dotenv with --no-dotenv after -c")) {
        return false;
    }
    if (!check(exitCode == 0, "dotenv with --no-dotenv after -c should exit 0")) {
        std::cerr << output << "\n";
        return false;
    }
    // .env should still be loaded — --no-dotenv is a Fennel arg, not a global flag
    return check(fs::exists(logs / "space.log"),
                 "log should use .env SPACE_LOG_DIR when --no-dotenv is after -c") &&
        check(!fs::exists(xdg / "space" / "log" / "space.log"),
              "log should NOT go to default XDG dir when --no-dotenv is after -c") &&
        check(!fs::exists(cwd / "gl.log"), "should not create cwd gl.log");
}

} // namespace

int main()
{
    if (!check(fs::exists(space_executable()), "space executable should exist in build dir")) {
        return 1;
    }
    bool ok = true;
    ok = test_default_log_path() && ok;
    ok = test_space_log_dir_override() && ok;
    ok = test_invalid_log_directory_fails_loudly() && ok;
    ok = test_dotenv_spacelogdir() && ok;
    ok = test_no_dotenv_skip() && ok;
    ok = test_dotenv_custom_path() && ok;
    ok = test_no_dotenv_after_c_is_fennel_arg() && ok;
    return ok ? 0 : 1;
}
