#include "live_dev_bootstrap.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <sol/sol.hpp>
#if defined(__linux__)
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace {
void check(bool condition, const char* message)
{
    if (!condition) throw std::runtime_error(message);
}

template<class F> void rejects(F action)
{
    bool rejected = false;
    try { action(); } catch (const std::exception&) { rejected = true; }
    check(rejected, "unsafe path was accepted");
}
}

int main(int argc, char** argv)
{
    namespace fs = std::filesystem;
#if defined(_WIN32)
    _putenv_s("SPACE_LIVE_DEV_TEST", "before dotenv = exact value");
#else
    setenv("SPACE_LIVE_DEV_TEST", "before dotenv = exact value", 1);
#endif
    char arg0[] = "space", arg1[] = "--dotenv", arg2[] = "settings file.env";
    char* args[] = {arg0, arg1, arg2};
    const auto executable = fs::canonical(argv[0]);
    const auto launch = live_dev::capture_launch(3, args, executable);
    check(launch.arguments == std::vector<std::string>{"--dotenv", "settings file.env"}, "argv changed");
    check(launch.cwd == fs::current_path(), "cwd changed");
#if defined(_WIN32)
    _putenv_s("SPACE_LIVE_DEV_TEST", "after dotenv");
#else
    setenv("SPACE_LIVE_DEV_TEST", "after dotenv", 1);
#endif
    sol::state lua;
    lua.open_libraries(sol::lib::base, sol::lib::table, sol::lib::string);
    const live_dev::BuildInfo build{"/native/source", "/native/build", "minimal", false};
    const auto bootstrap = live_dev::make_bootstrap(lua, launch, build);
    sol::table recipe = bootstrap["launch-recipe"]();
    check(recipe.get<std::string>("cwd") == launch.cwd.string(), "recipe cwd changed");
    sol::table env = recipe["environment"];
    check(env.get<std::string>("SPACE_LIVE_DEV_TEST") == "before dotenv = exact value", "environment was not captured before dotenv");
    sol::table arguments = recipe["argv"];
    check(arguments.get<std::string>(2) == "settings file.env", "recipe argv split");
    env["SPACE_LIVE_DEV_TEST"] = "mutated copy";
    sol::table recipe2 = bootstrap["launch-recipe"]();
    sol::table env2 = recipe2["environment"];
    check(env2.get<std::string>("SPACE_LIVE_DEV_TEST") == "before dotenv = exact value", "recipe leaked mutable native state");

#if defined(__linux__)
    const auto root = fs::temp_directory_path() / ("space-live-dev-test-" + std::to_string(getpid()));
    fs::create_directory(root);
    const auto checkout = root / "checkout";
    fs::create_directories(checkout / "assets/lua");
    std::ofstream(checkout / ".git") << "gitdir: elsewhere\n";
    const auto main_source = checkout / "assets/lua/main.fnl";
    std::ofstream(main_source) << "{}\n";
    sol::table source = bootstrap["describe-source"](main_source.string());
    check(source.get<std::string>("checkout-root") == fs::canonical(checkout).string(), "worktree checkout not resolved");
    check(source.get<std::string>("native-source-root") == "/native/source", "native/source provenance conflated");
    check(source.get<std::string>("source-root") == fs::canonical(main_source.parent_path()).string(), "wrong source root");
    check(source.get<int>("pid") == getpid(), "wrong pid");
    check(!source.get<std::string>("boot-id").empty(), "missing boot identity");
    check(!source.get<std::string>("process-start").empty(), "missing process start identity");
    const auto outside_source = root / "outside.fnl";
    std::ofstream(outside_source) << "{}\n";
    sol::table outside = bootstrap["describe-source"](outside_source.string());
    check(!outside["checkout-root"].valid(), "non-checkout unexpectedly registered");
    const auto runtime = root / "runtime";
    fs::create_directory(runtime);
    chmod(runtime.c_str(), 0700);
    setenv("XDG_RUNTIME_DIR", runtime.c_str(), 1);
    sol::table paths = bootstrap["private-paths"]("/example/checkout", "test-instance");
    check(paths.get<std::string>("checkout-key") == "dc103dda-5118-536d-9064-deb650dfc937", "UUIDv5 URL namespace differs from Python vector");
    const fs::path record = paths.get<std::string>("record");
    struct stat info {};
    check(stat(record.parent_path().c_str(), &info) == 0 && (info.st_mode & 0777) == 0700, "registry is not private");
    bootstrap["protect-file"](record.string());
    check(stat(record.c_str(), &info) == 0 && (info.st_mode & 0777) == 0600, "record is not private");
    check(paths.get<std::string>("endpoint").size() < 107, "IPC path too long");
    rejects([&] { bootstrap["private-paths"]("/example/checkout", "../escape"); });
    fs::remove(record);
    fs::create_symlink(main_source, record);
    rejects([&] { bootstrap["protect-file"](record.string()); });
    fs::remove(record);
    chmod(runtime.c_str(), 0777);
    rejects([&] { bootstrap["private-paths"]("/example/checkout", "another"); });
    chmod(runtime.c_str(), 0700);
    fs::remove_all(root);
#endif
    std::cout << "live-dev bootstrap tests passed\n";
}
