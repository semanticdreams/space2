#include "live_dev_bootstrap.h"

#include <boost/uuid/name_generator_sha1.hpp>
#include <boost/uuid/random_generator.hpp>
#include <boost/uuid/uuid_io.hpp>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <stdexcept>
#if defined(__linux__)
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif
#if defined(_WIN32)
#include <windows.h>
#else
extern char** environ;
#endif

namespace live_dev {
namespace {
namespace fs = std::filesystem;

std::string checkout_key(const std::string& checkout)
{
    return boost::uuids::to_string(boost::uuids::name_generator_sha1(
        boost::uuids::ns::url())("space-live-dev:" + checkout));
}

#if defined(__linux__)
std::string read_line(const char* path)
{
    std::ifstream input(path);
    std::string line;
    if (!std::getline(input, line)) throw std::runtime_error(std::string("Cannot read ") + path);
    return line;
}

std::string process_start()
{
    const auto line = read_line("/proc/self/stat");
    const auto close = line.rfind(')');
    if (close == std::string::npos) throw std::runtime_error("Invalid /proc/self/stat");
    std::istringstream fields(line.substr(close + 2));
    std::string value;
    for (int field = 3; field <= 22; ++field) {
        if (!(fields >> value)) throw std::runtime_error("Missing process start identity");
    }
    return value;
}

std::string executable_identity(const fs::path& path)
{
    struct stat info {};
    if (stat(path.c_str(), &info) != 0) throw std::runtime_error("Cannot stat executable: " + path.string());
    return std::to_string(info.st_dev) + ":" + std::to_string(info.st_ino) + ":" +
        std::to_string(info.st_size) + ":" + std::to_string(info.st_mtim.tv_sec) + ":" +
        std::to_string(info.st_mtim.tv_nsec);
}

void no_symlinks(const fs::path& path)
{
    fs::path current;
    for (const auto& component : fs::absolute(path)) {
        current /= component;
        struct stat info {};
        if (lstat(current.c_str(), &info) != 0 || S_ISLNK(info.st_mode)) {
            throw std::runtime_error("Unsafe runtime path: " + current.string());
        }
    }
}

void private_directory(const fs::path& path, bool create)
{
    if (create && mkdir(path.c_str(), 0700) != 0 && errno != EEXIST) {
        throw std::runtime_error("Cannot create private runtime directory: " + path.string());
    }
    no_symlinks(path);
    struct stat info {};
    if (lstat(path.c_str(), &info) != 0 || !S_ISDIR(info.st_mode) ||
        info.st_uid != getuid() || (info.st_mode & 0777) != 0700) {
        throw std::runtime_error("Runtime directory must be owned and mode 0700: " + path.string());
    }
}

fs::path runtime_base()
{
    const char* xdg = std::getenv("XDG_RUNTIME_DIR");
    if (xdg && *xdg) {
        if (!fs::path(xdg).is_absolute()) throw std::runtime_error("XDG_RUNTIME_DIR must be absolute");
        private_directory(xdg, false);
        const auto base = fs::path(xdg) / "space-live-dev";
        // Leave room for a short random socket name in sockaddr_un.sun_path.
        if (base.string().size() < 70) {
            private_directory(base, true);
            return base;
        }
    }
    const auto base = fs::path("/tmp") / ("space-live-dev-" + std::to_string(getuid()));
    private_directory(base, true);
    return base;
}

void protect_file(const fs::path& path)
{
    private_directory(path.parent_path(), false);
    const int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0600);
    if (fd < 0) throw std::runtime_error("Cannot protect runtime record: " + path.string());
    struct stat info {};
    const bool valid = fstat(fd, &info) == 0 && S_ISREG(info.st_mode) &&
        info.st_uid == getuid() && info.st_nlink == 1 && fchmod(fd, 0600) == 0;
    close(fd);
    if (!valid) throw std::runtime_error("Unsafe runtime record: " + path.string());
}
#endif
}

LaunchContext capture_launch(int argc, char** argv, const fs::path& executable)
{
    LaunchContext launch;
    launch.cwd = fs::current_path();
    launch.executable = fs::canonical(executable);
    for (int i = 1; i < argc; ++i) launch.arguments.emplace_back(argv[i]);
#if defined(_WIN32)
    const auto block = GetEnvironmentStringsA();
    if (!block) throw std::runtime_error("Cannot capture launch environment");
    for (const char* entry = block; *entry; entry += std::char_traits<char>::length(entry) + 1) {
        const std::string value(entry);
        const auto separator = value.find('=', value.front() == '=' ? 1 : 0);
        if (separator != std::string::npos) launch.environment.emplace(value.substr(0, separator), value.substr(separator + 1));
    }
    FreeEnvironmentStringsA(block);
#else
    for (char** entry = environ; entry && *entry; ++entry) {
        const std::string value(*entry);
        const auto separator = value.find('=');
        if (separator != std::string::npos) launch.environment.emplace(value.substr(0, separator), value.substr(separator + 1));
    }
#endif
    return launch;
}

sol::table make_bootstrap(sol::state& lua, const LaunchContext& launch, const BuildInfo& build)
{
    sol::state_view state(lua);
    sol::table bootstrap = state.create_table();
    const auto instance = boost::uuids::to_string(boost::uuids::random_generator()());
#if defined(__linux__)
    const auto boot = read_line("/proc/sys/kernel/random/boot_id");
    const auto start = process_start();
#endif
    bootstrap.set_function("describe-source", [=](const std::string& path, sol::this_state ts) {
        sol::state_view state(ts);
        sol::table result = state.create_table();
        const auto main = fs::canonical(path);
        result["main-source"] = main.string();
        result["source-root"] = main.parent_path().string();
        result["instance-id"] = instance;
        result["executable"] = launch.executable.string();
        result["native-source-root"] = build.source_dir;
        result["native-build-root"] = build.binary_dir;
        result["build-profile"] = build.profile;
        result["cef-enabled"] = build.cef_enabled;
#if defined(__linux__)
        result["pid"] = getpid();
        result["uid"] = getuid();
        result["boot-id"] = boot;
        result["process-start"] = start;
        result["executable-identity"] = executable_identity(launch.executable);
        for (auto dir = main.parent_path(); !dir.empty(); dir = dir.parent_path()) {
            if (fs::is_directory(dir / ".git") || fs::is_regular_file(dir / ".git")) {
                result["checkout-root"] = fs::canonical(dir).string();
                break;
            }
            if (dir == dir.parent_path()) break;
        }
#endif
        return result;
    });
    bootstrap.set_function("private-paths", [](const std::string& checkout, const std::string& id, sol::this_state ts) {
        sol::state_view state(ts);
        sol::table paths = state.create_table();
#if defined(__linux__)
        if (id.empty() || id.size() > 64 || id.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-") != std::string::npos) {
            throw std::runtime_error("Invalid live-dev instance id");
        }
        const auto base = runtime_base();
        const auto key = checkout_key(checkout);
        const auto partition = base / key;
        private_directory(partition, true);
        const auto instances = partition / "instances";
        private_directory(instances, true);
        const auto socket = base / ("s-" + boost::uuids::to_string(boost::uuids::random_generator()()).substr(0, 18));
        paths["checkout-key"] = key;
        paths["record"] = (instances / (id + ".json")).string();
        paths["endpoint"] = "ipc://" + socket.string();
#endif
        return paths;
    });
    bootstrap.set_function("protect-file", [](const std::string& path) {
#if defined(__linux__)
        protect_file(path);
#else
        throw std::runtime_error("Linux live-dev records are unavailable on this platform");
#endif
    });
    bootstrap.set_function("launch-recipe", [launch](sol::this_state ts) {
        sol::state_view state(ts);
        sol::table recipe = state.create_table();
        recipe["executable"] = launch.executable.string();
        recipe["cwd"] = launch.cwd.string();
        sol::table args = state.create_table();
        for (std::size_t i = 0; i < launch.arguments.size(); ++i) args[i + 1] = launch.arguments[i];
        recipe["argv"] = args;
        sol::table env = state.create_table();
        for (const auto& entry : launch.environment) env[entry.first] = entry.second;
        recipe["environment"] = env;
        return recipe;
    });
    return bootstrap;
}
}
