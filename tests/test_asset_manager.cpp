#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include "asset_manager.h"

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

class ScopedEnv {
public:
    ScopedEnv(std::string key, std::optional<std::string> value) : key_(std::move(key))
    {
        const char* existing = std::getenv(key_.c_str());
        if (existing) {
            old_ = std::string(existing);
        }
        ok_ = value ? set_env_var(key_, *value) : unset_env_var(key_);
    }

    ~ScopedEnv()
    {
        if (old_) {
            set_env_var(key_, *old_);
        } else {
            unset_env_var(key_);
        }
    }

    bool ok() const { return ok_; }

private:
    std::string key_;
    std::optional<std::string> old_;
    bool ok_ = false;
};

class ScopedCwd {
public:
    explicit ScopedCwd(const fs::path& next) : old_(fs::current_path()) { fs::current_path(next); }
    ~ScopedCwd()
    {
        std::error_code ec;
        fs::current_path(old_, ec);
    }
private:
    fs::path old_;
};

fs::path make_temp_root(const std::string& name)
{
    auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    fs::path root = fs::temp_directory_path() / (name + "_" + std::to_string(stamp));
    fs::create_directories(root);
    return root;
}

void touch(const fs::path& path)
{
    fs::create_directories(path.parent_path());
    std::ofstream out(path);
    out << "asset\n";
}

bool check(bool condition, const std::string& message)
{
    if (!condition) {
        std::cerr << "FAIL: " << message << "\n";
        return false;
    }
    return true;
}

bool path_equals(const std::string& actual, const fs::path& expected)
{
    std::error_code ec1;
    std::error_code ec2;
    return fs::weakly_canonical(actual, ec1) == fs::weakly_canonical(expected, ec2);
}

char path_list_separator()
{
#if defined(_WIN32)
    return ';';
#else
    return ':';
#endif
}

std::string join_path_list(const std::vector<fs::path>& roots)
{
    std::string result;
    for (size_t i = 0; i < roots.size(); i++) {
        if (i > 0) {
            result.push_back(path_list_separator());
        }
        result += roots[i].string();
    }
    return result;
}

size_t count_occurrences(const std::string& haystack, const std::string& needle)
{
    size_t count = 0;
    size_t pos = 0;
    while ((pos = haystack.find(needle, pos)) != std::string::npos) {
        count++;
        pos += needle.size();
    }
    return count;
}

bool test_space_assets_path_supports_multiple_ordered_roots()
{
    fs::path root = make_temp_root("space_asset_env_list");
    ScopedEnv env("SPACE_ASSETS_PATH", join_path_list({
        root / "env_missing",
        root / "env_second",
        root / "env_third"
    }));
    ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
    fs::create_directories(root / "work");
    ScopedCwd cwd(root / "work");
    AssetManager::clearExecutablePathForTests();
    AssetManager::setExecutablePath(root / "bin" / "space");

    touch(root / "env_second" / "probe.txt");
    touch(root / "env_third" / "probe.txt");
    touch(root / "work" / "assets" / "probe.txt");

    return check(path_equals(AssetManager::getAssetPath("probe.txt"), root / "env_second" / "probe.txt"),
                 "second SPACE_ASSETS_PATH entry should win when the first entry lacks the asset");
}

bool test_env_override_has_highest_priority()
{
    fs::path root = make_temp_root("space_asset_env");
    ScopedEnv env("SPACE_ASSETS_PATH", (root / "env").string());
    ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
    fs::create_directories(root / "cwd");
    ScopedCwd cwd(root / "cwd");
    AssetManager::clearExecutablePathForTests();
    AssetManager::setExecutablePath(root / "bin" / "space");

    touch(root / "env" / "probe.txt");
    touch(root / "xdg" / "space" / "assets" / "probe.txt");
    touch(root / "bin" / "assets" / "probe.txt");
    touch(root / "cwd" / "assets" / "probe.txt");

    return check(path_equals(AssetManager::getAssetPath("probe.txt"), root / "env" / "probe.txt"),
                 "SPACE_ASSETS_PATH should win when it contains the asset");
}

bool test_user_data_precedes_executable_assets()
{
    fs::path root = make_temp_root("space_asset_user");
    ScopedEnv env("SPACE_ASSETS_PATH", std::nullopt);
    ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
    fs::create_directories(root / "cwd");
    ScopedCwd cwd(root / "cwd");
    AssetManager::clearExecutablePathForTests();
    AssetManager::setExecutablePath(root / "bin" / "space");

    touch(root / "xdg" / "space" / "assets" / "probe.txt");
    touch(root / "bin" / "assets" / "probe.txt");

    return check(path_equals(AssetManager::getAssetPath("probe.txt"), root / "xdg" / "space" / "assets" / "probe.txt"),
                 "user data assets should precede executable assets");
}

bool test_cwd_assets_precede_user_data_and_executable_assets()
{
    fs::path root = make_temp_root("space_asset_cwd_order");
    ScopedEnv env("SPACE_ASSETS_PATH", std::nullopt);
    ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
    fs::create_directories(root / "work");
    ScopedCwd cwd(root / "work");
    AssetManager::clearExecutablePathForTests();
    AssetManager::setExecutablePath(root / "bin" / "space");

    touch(root / "work" / "assets" / "probe.txt");
    touch(root / "xdg" / "space" / "assets" / "probe.txt");
    touch(root / "bin" / "assets" / "probe.txt");

    return check(path_equals(AssetManager::getAssetPath("probe.txt"), root / "work" / "assets" / "probe.txt"),
                 "cwd/assets should precede user-data and executable assets");
}

bool test_user_data_precedes_executable_assets_when_cwd_missing()
{
    fs::path root = make_temp_root("space_asset_user_after_cwd");
    ScopedEnv env("SPACE_ASSETS_PATH", std::nullopt);
    ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
    fs::create_directories(root / "work");
    ScopedCwd cwd(root / "work");
    AssetManager::clearExecutablePathForTests();
    AssetManager::setExecutablePath(root / "bin" / "space");

    touch(root / "xdg" / "space" / "assets" / "probe.txt");
    touch(root / "bin" / "assets" / "probe.txt");

    return check(path_equals(AssetManager::getAssetPath("probe.txt"), root / "xdg" / "space" / "assets" / "probe.txt"),
                 "user-data assets should precede executable assets when cwd/assets lacks the asset");
}

bool test_space_assets_path_ignores_empty_entries()
{
    fs::path root = make_temp_root("space_asset_env_empty");
    std::string value;
    value.push_back(path_list_separator());
    value += (root / "env").string();
    value.push_back(path_list_separator());

    ScopedEnv env("SPACE_ASSETS_PATH", value);
    ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
    fs::create_directories(root / "work");
    ScopedCwd cwd(root / "work");
    AssetManager::clearExecutablePathForTests();

    touch(root / "env" / "probe.txt");

    return check(path_equals(AssetManager::getAssetPath("probe.txt"), root / "env" / "probe.txt"),
                 "empty SPACE_ASSETS_PATH entries should be ignored");
}

bool test_deduplicates_equivalent_roots_in_missing_diagnostics()
{
    fs::path root = make_temp_root("space_asset_dedup");
    fs::path workAssets = root / "work" / "assets";
    ScopedEnv env("SPACE_ASSETS_PATH", workAssets.string());
    ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
    fs::create_directories(workAssets);
    ScopedCwd cwd(root / "work");
    AssetManager::clearExecutablePathForTests();

    try {
        (void)AssetManager::getAssetPath("missing.asset");
    } catch (const std::runtime_error& e) {
        std::string message = e.what();
        std::string searchedPath = (workAssets / "missing.asset").string();
        return check(count_occurrences(message, searchedPath) == 1,
                     "deduplicated roots should appear once in missing diagnostics") &&
               check(message.find("deduplicated") == std::string::npos,
                     "missing diagnostics should not include duplicate-root noise");
    }

    std::cerr << "FAIL: missing dedup asset should throw\n";
    return false;
}

bool test_executable_sibling_assets_work_from_unrelated_cwd()
{
    fs::path root = make_temp_root("space_asset_sibling");
    ScopedEnv env("SPACE_ASSETS_PATH", std::nullopt);
    ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
    fs::create_directories(root / "unrelated");
    ScopedCwd cwd(root / "unrelated");
    AssetManager::clearExecutablePathForTests();
    AssetManager::setExecutablePath(root / "bin" / "space");

    touch(root / "bin" / "assets" / "lua" / "marker.txt");
    return check(path_equals(AssetManager::getAssetPath("lua"), root / "bin" / "assets" / "lua"),
                 "executable sibling assets should be found from unrelated CWD");
}

bool test_executable_relative_share_assets_work()
{
    fs::path root = make_temp_root("space_asset_share");
    ScopedEnv env("SPACE_ASSETS_PATH", std::nullopt);
    ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
    fs::create_directories(root / "work");
    ScopedCwd cwd(root / "work");
    AssetManager::clearExecutablePathForTests();
    AssetManager::setExecutablePath(root / "pkg" / "bin" / "space");

    touch(root / "pkg" / "share" / "space" / "assets" / "lua" / "marker.txt");
    return check(path_equals(AssetManager::getAssetPath("lua"), root / "pkg" / "share" / "space" / "assets" / "lua"),
                 "executable-relative ../share/space/assets should be found");
}

bool test_cwd_assets_fallback_remains()
{
    fs::path root = make_temp_root("space_asset_cwd");
    ScopedEnv env("SPACE_ASSETS_PATH", std::nullopt);
    ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
    fs::create_directories(root / "work");
    ScopedCwd cwd(root / "work");
    AssetManager::clearExecutablePathForTests();
    AssetManager::setExecutablePath(root / "bin" / "space");

    touch(root / "work" / "assets" / "lua" / "marker.txt");
    return check(path_equals(AssetManager::getAssetPath("lua"), root / "work" / "assets" / "lua"),
                 "existing CWD assets fallback should remain");
}

bool test_missing_error_lists_requested_asset_and_searched_paths()
{
    fs::path root = make_temp_root("space_asset_missing");
    ScopedEnv env("SPACE_ASSETS_PATH", (root / "env").string());
    ScopedEnv xdg("XDG_DATA_HOME", (root / "xdg").string());
    fs::create_directories(root / "work");
    ScopedCwd cwd(root / "work");
    AssetManager::clearExecutablePathForTests();
    AssetManager::setExecutablePath(root / "pkg" / "bin" / "space");

    try {
        (void)AssetManager::getAssetPath("missing.asset");
    } catch (const std::runtime_error& e) {
        std::string message = e.what();
        std::vector<std::string> expected = {
            "Asset not found: missing.asset",
            (root / "env" / "missing.asset").string(),
            (root / "work" / "assets" / "missing.asset").string(),
            (root / "xdg" / "space" / "assets" / "missing.asset").string(),
            (root / "pkg" / "bin" / "assets" / "missing.asset").string(),
            (root / "pkg" / "share" / "space" / "assets" / "missing.asset").string(),
            (root / "pkg" / "Resources" / "assets" / "missing.asset").string(),
            "/usr/share/space/assets/missing.asset",
        };
        for (const std::string& text : expected) {
            if (!check(message.find(text) != std::string::npos, "missing error should include: " + text)) {
                std::cerr << "actual: " << message << "\n";
                return false;
            }
        }
        return true;
    }

    std::cerr << "FAIL: missing asset should throw\n";
    return false;
}

bool test_absolute_path_is_rejected()
{
    fs::path root = make_temp_root("space_asset_abs_reject");
    ScopedEnv env("SPACE_ASSETS_PATH", std::nullopt);
    ScopedEnv xdg("XDG_DATA_HOME", std::nullopt);
    fs::create_directories(root / "cwd");
    ScopedCwd cwd(root / "cwd");
    AssetManager::clearExecutablePathForTests();

    // /etc/hostname should exist on Linux and must not be reachable
    // via an absolute relativePath argument.
    try {
        (void)AssetManager::getAssetPath("/etc/hostname");
        return check(false, "absolute path should throw");
    } catch (const std::runtime_error& e) {
        return check(std::string(e.what()).find("absolute") != std::string::npos,
                     "absolute path error should mention 'absolute'");
    }
}

bool test_parent_traversal_escaping_root_is_rejected()
{
    fs::path root = make_temp_root("space_asset_parent_reject");
    ScopedEnv env("SPACE_ASSETS_PATH", (root / "env").string());
    ScopedEnv xdg("XDG_DATA_HOME", std::nullopt);
    fs::create_directories(root / "cwd");
    ScopedCwd cwd(root / "cwd");
    AssetManager::clearExecutablePathForTests();
    AssetManager::setExecutablePath(root / "bin" / "space");

    // Create a legitimate asset and an out-of-root file
    touch(root / "env" / "probe.txt");

    fs::path sensitiveFile = root / "sensitive.txt";
    touch(sensitiveFile);

    // Try to reach sensitiveFile via parent-traversing relative path.
    // The env root is root/env; ../../sensitive.txt escapes that root.
    try {
        (void)AssetManager::getAssetPath("../../sensitive.txt");
        return check(false, "parent traversal should throw");
    } catch (const std::runtime_error& e) {
        std::string message = e.what();
        return check(message.find("outside root") != std::string::npos,
                     "parent traversal error should mention 'outside root'");
    }
}

} // namespace

int main()
{
    bool ok = true;
    ok = test_space_assets_path_supports_multiple_ordered_roots() && ok;
    ok = test_env_override_has_highest_priority() && ok;
    ok = test_cwd_assets_precede_user_data_and_executable_assets() && ok;
    ok = test_user_data_precedes_executable_assets() && ok;
    ok = test_user_data_precedes_executable_assets_when_cwd_missing() && ok;
    ok = test_space_assets_path_ignores_empty_entries() && ok;
    ok = test_deduplicates_equivalent_roots_in_missing_diagnostics() && ok;
    ok = test_executable_sibling_assets_work_from_unrelated_cwd() && ok;
    ok = test_executable_relative_share_assets_work() && ok;
    ok = test_cwd_assets_fallback_remains() && ok;
    ok = test_missing_error_lists_requested_asset_and_searched_paths() && ok;
    ok = test_absolute_path_is_rejected() && ok;
    ok = test_parent_traversal_escaping_root_is_rejected() && ok;
    AssetManager::clearExecutablePathForTests();
    return ok ? 0 : 1;
}
