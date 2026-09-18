#ifndef WINDOW_SDL_H
#define WINDOW_SDL_H

#include <SDL3/SDL.h>

#include <memory>
#include <string>

#include <epoxy/gl.h>

#include "log.h"

extern const float SCREEN_WIDTH;
extern const float SCREEN_HEIGHT;
extern LogConfig LOG_CONFIG;

std::string format_window_title_with_fps(const std::string& title, double fps);

// Used by SDL_Window unique pointer
struct SdlWindowDestroyer {
    void operator()(SDL_Window* window) const {
        SDL_DestroyWindow(window);
    }
};

enum class WindowStartupMode {
    Windowed,
    Maximized,
    Fullscreen,
};

// Manage game's window and drawing in this window.
// The window title bar gives some info, as game's title
// or FPS counter.
class WindowSdl {
public:
    explicit WindowSdl(std::string  title);

    ~WindowSdl() ;

    WindowSdl() = delete;

    WindowSdl(const WindowSdl&) = delete;

    WindowSdl& operator=(const WindowSdl&) = delete;

    bool init(int width, int height, WindowStartupMode startup_mode);

    void logGlParams() ;

    void updateFpsCounter(Uint64 dt) ;

    void clear() ;

    void swapBuffer() ;

    void clean() ;

    static std::unique_ptr<WindowSdl> create(std::string title = "space");

    void toggleFullscreen();
    void setTextInputEnabled(bool enabled);
    [[nodiscard]] bool isTextInputEnabled() const;
    [[nodiscard]] WindowStartupMode currentStartupMode() const;
    [[nodiscard]] bool getWindowSize(int& out_width, int& out_height) const;
    [[nodiscard]] bool getWindowSizeInPixels(int& out_width, int& out_height) const;
    void updateViewportFromWindowPixels();

private:
    std::unique_ptr<SDL_Window, SdlWindowDestroyer> window;
    SDL_GLContext context {};
    std::string title;

    double previousSeconds { 0 };
    double currentSeconds { 0 };
    int frameCount { 0 };

    /*
    void debugGlErrorCallback(  GLenum        source,
                                GLenum        type,
                                GLuint        id,
                                GLenum        severity,
                                GLsizei       length,
                                const GLchar* message,
                                GLvoid*       userParam);

    const char* debugGlSeverityToStr(GLenum severity);
    const char* debugGlTypeToStr(GLenum type);
    const char* debugGlSourceToStr(GLenum source);
    */
};

#endif
