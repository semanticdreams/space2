#include "window_sdl.h"

#include <iostream>
#include <memory>
#include <string>

LogConfig LOG_CONFIG = {};

int main()
{
    const std::string formatted = format_window_title_with_fps("Snake", 60.0);
    if (formatted.rfind("Snake @ fps:", 0) != 0) {
        std::cerr << "expected formatted title to start with 'Snake @ fps:', got '"
                  << formatted << "'\n";
        return 1;
    }
    if (formatted.find("space @ fps:") != std::string::npos) {
        std::cerr << "formatted title should not contain default title prefix, got '"
                  << formatted << "'\n";
        return 1;
    }

    std::unique_ptr<WindowSdl> window = WindowSdl::create("Snake");
    if (window == nullptr) {
        std::cerr << "WindowSdl::create returned null for explicit title\n";
        return 1;
    }

    return 0;
}
