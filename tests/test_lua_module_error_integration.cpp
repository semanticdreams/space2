#include <array>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <string>
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

} // namespace

int main()
{
    const fs::path assets_dir = fs::current_path().parent_path() / "assets";
    const fs::path fennel_file_error = assets_dir / "lua" / "tests" / "file-error.fnl";
    const fs::path lua_file_error = assets_dir / "lua" / "tests" / "lua-file-error.lua";
#if defined(_WIN32)
    const fs::path executable = fs::current_path() / "space-cli.exe";
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

    std::string output;
    int exit_code = 0;
    if (!check(run_command_capture(build_command(executable, {"--bad-option"}), output, exit_code),
               "run invalid global option command")) {
        return 1;
    }
    if (!check(exit_code == 109, "invalid global option should preserve CLI11 exit code")) {
        std::cerr << output << "\n";
        return 1;
    }
    if (!check(output.find("--bad-option") != std::string::npos,
               "invalid global option should report the rejected option")) {
        std::cerr << output << "\n";
        return 1;
    }

    return 0;
}
