#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <vector>

#include "appdirs.h"
#include "asset_manager.h"

namespace fs = std::filesystem;

namespace {

const std::string systemAssetsRoot = "/usr/share/space/assets";
std::optional<fs::path> executablePath;

struct Candidate {
    fs::path root;
    std::string label;
};

fs::path normalized(const fs::path& path)
{
    std::error_code ec;
    fs::path result = fs::weakly_canonical(fs::absolute(path, ec), ec);
    return ec ? fs::absolute(path).lexically_normal() : result;
}

std::string dedup_key(const fs::path& root)
{
    std::error_code ec;
    fs::path norm = fs::weakly_canonical(fs::absolute(root, ec), ec);
    if (ec) {
        norm = fs::absolute(root).lexically_normal();
    }
    return norm.string();
}

bool is_contained_under(const fs::path& full, const fs::path& root)
{
    std::error_code ec;
    fs::path canonFull = fs::weakly_canonical(fs::absolute(full, ec), ec);
    if (ec) {
        canonFull = fs::absolute(full).lexically_normal();
    }
    ec.clear();
    fs::path canonRoot = fs::weakly_canonical(fs::absolute(root, ec), ec);
    if (ec) {
        canonRoot = fs::absolute(root).lexically_normal();
    }
    auto [m1, m2] = std::mismatch(
        canonFull.begin(), canonFull.end(),
        canonRoot.begin(), canonRoot.end());
    return m2 == canonRoot.end();
}

char path_list_separator()
{
#if defined(_WIN32)
    return ';';
#else
    return ':';
#endif
}

std::vector<fs::path> split_asset_path_list(const char* value)
{
    std::vector<fs::path> roots;
    if (value == nullptr || value[0] == '\0') {
        return roots;
    }

    std::string list(value);
    size_t start = 0;
    while (start <= list.size()) {
        size_t end = list.find(path_list_separator(), start);
        std::string segment = list.substr(start, end == std::string::npos ? std::string::npos : end - start);
        if (!segment.empty()) {
            roots.emplace_back(segment);
        }
        if (end == std::string::npos) {
            break;
        }
        start = end + 1;
    }

    return roots;
}

std::vector<Candidate> build_asset_candidates()
{
    std::vector<Candidate> candidates;
    std::vector<std::string> dedupKeys;

    auto addCandidate = [&](const fs::path& root, const std::string& label) {
        std::string key = dedup_key(root);
        for (const std::string& existing : dedupKeys) {
            if (existing == key) {
                return;
            }
        }
        dedupKeys.push_back(key);
        candidates.push_back({root, label});
    };

    for (const fs::path& root : split_asset_path_list(std::getenv("SPACE_ASSETS_PATH"))) {
        addCandidate(root, "SPACE_ASSETS_PATH");
    }

    addCandidate(fs::current_path() / "assets", "cwd");
    addCandidate(fs::path(get_user_data_dir("space")) / "assets", "user-data");

    if (executablePath.has_value()) {
        fs::path exeDir = executablePath->parent_path();
        addCandidate(exeDir / "assets", "executable-sibling");
        addCandidate(exeDir / ".." / "share" / "space" / "assets", "executable-share");
        addCandidate(exeDir / ".." / "Resources" / "assets", "executable-resources");
    }

    addCandidate(fs::path(systemAssetsRoot), "system");

    return candidates;
}

} // namespace

void AssetManager::setExecutablePath(const fs::path& path)
{
    if (path.empty()) {
        executablePath = std::nullopt;
    } else {
        executablePath = normalized(path);
    }
}

void AssetManager::clearExecutablePathForTests()
{
    executablePath = std::nullopt;
}

std::vector<fs::path> AssetManager::getAssetRoots()
{
    std::vector<fs::path> roots;
    for (const Candidate& candidate : build_asset_candidates()) {
        roots.push_back(candidate.root);
    }
    return roots;
}

std::string AssetManager::getAssetPath(const std::string& relativePath)
{
    // Reject absolute paths — asset discovery only works with relative paths
    // that are resolved under configured asset roots.
    if (fs::path(relativePath).is_absolute()) {
        throw std::runtime_error("Asset not found: " + relativePath +
                                 " (absolute paths are not supported)");
    }

    std::vector<Candidate> candidates = build_asset_candidates();
    std::vector<std::string> searched;

    // Probe candidates in order
    for (const auto& candidate : candidates) {
        fs::path fullPath = (candidate.root / relativePath).lexically_normal();
        if (!is_contained_under(fullPath, candidate.root)) {
            searched.push_back(candidate.label + ": " + fullPath.string() + " (outside root)");
            continue;
        }
        std::error_code ec;
        if (fs::exists(fullPath, ec)) {
            return fs::absolute(fullPath).string();
        }
        searched.push_back(candidate.label + ": " + fullPath.string());
    }

    // Not found — build diagnostic error
    std::ostringstream oss;
    oss << "Asset not found: " << relativePath << "\nSearched paths:\n";
    for (const std::string& s : searched) {
        oss << "  " << s << "\n";
    }
    throw std::runtime_error(oss.str());
}
