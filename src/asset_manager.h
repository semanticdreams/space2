#pragma once

#include <filesystem>
#include <string>
#include <vector>

class AssetManager {
public:
    static std::string getAssetPath(const std::string& relativePath);
    static std::vector<std::filesystem::path> getAssetRoots();
    static void setExecutablePath(const std::filesystem::path& executablePath);
    static void clearExecutablePathForTests();
};
