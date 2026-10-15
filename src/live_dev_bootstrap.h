#pragma once

#include <filesystem>
#include <map>
#include <string>
#include <vector>
#include <sol/sol.hpp>

namespace live_dev {
struct LaunchContext {
    std::filesystem::path cwd;
    std::filesystem::path executable;
    std::vector<std::string> arguments;
    std::map<std::string, std::string> environment;
};

struct BuildInfo {
    std::string source_dir;
    std::string binary_dir;
    std::string profile;
    bool cef_enabled;
};

LaunchContext capture_launch(int argc, char** argv, const std::filesystem::path& executable);
sol::table make_bootstrap(sol::state& lua, const LaunchContext& launch, const BuildInfo& build);
}
