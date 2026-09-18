#include <cstdio>
#include <iostream>
#include <utility>

#define LOG_SUBSYSTEM "window"

#include "window_sdl.h"
#include "gl_debug.hpp"
#include "asset_manager.h"
#include "image_loader.h"

std::string format_window_title_with_fps(const std::string& title, double fps)
{
    char tmp[128];
#if __linux__
    snprintf(tmp, sizeof(tmp), "%s @ fps: %.2f", title.c_str(), fps);
#else
    sprintf_s(tmp, "%s @ fps: %.2f", title.c_str(), fps);
#endif
    return std::string(tmp);
}

WindowSdl::WindowSdl(std::string title) : title(std::move(title)) {
}

WindowSdl::~WindowSdl() {
    SDL_Quit();
    LOG(Info) << "Bye :)";
}

namespace {

void log_sdl_warning(const char* context)
{
    const char* error = SDL_GetError();
    if (error && error[0] != '\0') {
        LOG(Warning) << context << ": " << error;
    }
    SDL_ClearError();
}

void sync_window_if_possible(SDL_Window* window, const char* context)
{
    if (!SDL_SyncWindow(window)) {
        log_sdl_warning(context);
    }
}

} // namespace

bool WindowSdl::init(int width, int height, WindowStartupMode startup_mode) {
    SDL_WindowFlags flags = SDL_WINDOW_OPENGL
                            | SDL_WINDOW_RESIZABLE
                            | SDL_WINDOW_HIGH_PIXEL_DENSITY
                            | SDL_WINDOW_HIDDEN;

    SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
    SDL_SetHint(SDL_HINT_VIDEO_ALLOW_SCREENSAVER, "1");
    SDL_SetHint(SDL_HINT_SCREENSAVER_INHIBIT_ACTIVITY_NAME, "Space runtime performance policy");

    const SDL_InitFlags init_flags = SDL_INIT_VIDEO | SDL_INIT_EVENTS;
    if (!SDL_Init(init_flags)) {
        LOG(Error) << "SDL initialisation failed";
        LOG(Error) << SDL_GetError();
        return false;
    } else {
        LOG(Info) << "Subsystems initialised";
        if (!SDL_InitSubSystem(SDL_INIT_GAMEPAD)) {
            LOG(Warning) << "SDL gamepad subsystem unavailable: " << SDL_GetError();
            SDL_ClearError();
        }
        if (!SDL_InitSubSystem(SDL_INIT_JOYSTICK)) {
            LOG(Warning) << "SDL joystick subsystem unavailable: " << SDL_GetError();
            SDL_ClearError();
        }
        if (!SDL_InitSubSystem(SDL_INIT_HAPTIC)) {
            LOG(Warning) << "SDL haptic subsystem unavailable: " << SDL_GetError();
            SDL_ClearError();
        }

        SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);

        SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
        SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);

        SDL_GL_SetAttribute(SDL_GL_CONTEXT_FLAGS, SDL_GL_CONTEXT_DEBUG_FLAG);

        int create_width = width;
        int create_height = height;
        if (startup_mode != WindowStartupMode::Windowed) {
            SDL_DisplayID primary_display = SDL_GetPrimaryDisplay();
            SDL_Rect usable_bounds {};
            if (primary_display != 0 && SDL_GetDisplayUsableBounds(primary_display, &usable_bounds)) {
                create_width = usable_bounds.w;
                create_height = usable_bounds.h;
            } else {
                SDL_ClearError();
            }
        }

        // WindowSdl
        window = std::unique_ptr<SDL_Window, SdlWindowDestroyer>(
                SDL_CreateWindow(title.c_str(), create_width, create_height, flags));
        if (window) {
            LOG(Info) << "WindowSdl initialised";
        } else
            return false;

        if (startup_mode == WindowStartupMode::Windowed) {
            if (!SDL_SetWindowSize(window.get(), width, height)) {
                log_sdl_warning("Failed to set startup window size");
            }
        }

        if (startup_mode == WindowStartupMode::Maximized) {
            if (!SDL_MaximizeWindow(window.get())) {
                LOG(Error) << "Failed to request maximized startup mode: " << SDL_GetError();
                return false;
            }
        } else if (startup_mode == WindowStartupMode::Fullscreen) {
            if (!SDL_SetWindowFullscreen(window.get(), true)) {
                LOG(Error) << "Failed to request fullscreen startup mode: " << SDL_GetError();
                return false;
            }
        }

        sync_window_if_possible(window.get(), "Failed to sync startup window state");
        if (!SDL_ShowWindow(window.get())) {
            LOG(Error) << "Failed to show window: " << SDL_GetError();
            return false;
        }
        sync_window_if_possible(window.get(), "Failed to sync shown window state");

        // Set icon
        auto iconPath = AssetManager::getAssetPath("pics/space.png");
        ImageBuffer icon;
        std::string error;
        if (load_png_file(iconPath, icon, error)) {
            // Create an SDL_Surface from pixel data
            SDL_Surface* iconSurface = SDL_CreateSurfaceFrom(
                    icon.width,
                    icon.height,
                    SDL_PIXELFORMAT_RGBA32,
                    icon.pixels.get(),
                    icon.width * 4);

            if (iconSurface) {
                SDL_SetWindowIcon(window.get(), iconSurface);
                SDL_DestroySurface(iconSurface);
            } else {
                LOG(Warning) << "Failed to create SDL surface from icon pixels!";
            }
        } else {
            LOG(Warning) << "Failed to load icon PNG: " << iconPath;
        }

        // OpenGL context
        context = SDL_GL_CreateContext(window.get());
        if (context) {
            LOG(Info) << "OpenGL Context initialised";
        } else
            return false;

        // OpenGL loader (epoxy)
        LOG(Info) << "Epoxy OpenGL loader active";


        // Get graphics info
        const GLubyte* renderer = glGetString(GL_RENDERER);
        const GLubyte* version = glGetString(GL_VERSION);
        LOG(Info) << "Renderer: " << renderer;
        LOG(Info) << "OpenGL version supported " << version;

        updateViewportFromWindowPixels();
        //glEnable(GL_CULL_FACE);
        glEnable(GL_BLEND);
        //glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);

        if (glDebugMessageControlARB != nullptr) {
            glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS);
            glDebugMessageCallback((GLDEBUGPROCARB) debugGlErrorCallback, nullptr);
            glDebugMessageControl(GL_DONT_CARE, GL_DONT_CARE, GL_DEBUG_SEVERITY_NOTIFICATION, 0, nullptr, GL_FALSE);
        }

        return true;
    }
}

void WindowSdl::logGlParams() {
    GLenum params[] = {
            GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS,
            GL_MAX_CUBE_MAP_TEXTURE_SIZE,
            GL_MAX_DRAW_BUFFERS,
            GL_MAX_FRAGMENT_UNIFORM_COMPONENTS,
            GL_MAX_TEXTURE_IMAGE_UNITS,
            GL_MAX_TEXTURE_SIZE,
            GL_MAX_VARYING_FLOATS,
            GL_MAX_VERTEX_ATTRIBS,
            GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS,
            GL_MAX_VERTEX_UNIFORM_COMPONENTS,
            GL_MAX_VIEWPORT_DIMS,
            GL_STEREO,
    };
    const char* names[] = {
            "GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS",
            "GL_MAX_CUBE_MAP_TEXTURE_SIZE",
            "GL_MAX_DRAW_BUFFERS",
            "GL_MAX_FRAGMENT_UNIFORM_COMPONENTS",
            "GL_MAX_TEXTURE_IMAGE_UNITS",
            "GL_MAX_TEXTURE_SIZE",
            "GL_MAX_VARYING_FLOATS",
            "GL_MAX_VERTEX_ATTRIBS",
            "GL_MAX_VERTEX_TEXTURE_IMAGE_UNITS",
            "GL_MAX_VERTEX_UNIFORM_COMPONENTS",
            "GL_MAX_VIEWPORT_DIMS",
            "GL_STEREO",
    };
    LOG(Info) << "-----------------------------";
    LOG(Info) << "GL Context Params:";
    // integers - only works if the order is 0-10 integer return types
    for (int i = 0; i < 10; i++) {
        int v = 0;
        glGetIntegerv(params[i], &v);
        LOG(Info) << names[i] << " " << v;
    }
    // others
    int v[2];
    v[0] = v[1] = 0;
    glGetIntegerv(params[10], v);
    LOG(Info) << names[10] << " " << v[0] << " " << v[1];
    unsigned char s = 0;
    glGetBooleanv(params[11], &s);
    LOG(Info) << names[11] << " " << (unsigned int) s;
    LOG(Info) << "";
}

void WindowSdl::updateFpsCounter(Uint64 dt) {
    double elapsedSeconds;

    currentSeconds += static_cast<double>(dt) / 1000.0;
    elapsedSeconds = currentSeconds - previousSeconds;
    /* limit text updates to 4 per second */
    if (elapsedSeconds > 0.25) {
        previousSeconds = currentSeconds;
        double fps = (double) frameCount / elapsedSeconds;
        const std::string window_title = format_window_title_with_fps(title, fps);
        SDL_SetWindowTitle(window.get(), window_title.c_str());
        frameCount = 0;
    }
    frameCount++;
}

void WindowSdl::clear() {
    glClearColor(0.0f, 0.0f, 0.2f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
}

void WindowSdl::swapBuffer() {
    // Check OpenGL error
    GLenum err;
    while ((err = glGetError()) != GL_NO_ERROR) {
        LOG(Error) << "OpenGL error: " << err;
    }

    SDL_GL_SwapWindow(window.get());
}

void WindowSdl::clean() {
    // SDL_DestroyWindow(window); Handled by unique_ptr
    setTextInputEnabled(false);
    SDL_GL_DestroyContext(context);
}

std::unique_ptr<WindowSdl> WindowSdl::create(std::string title) {
    return std::make_unique<WindowSdl>(std::move(title));
}

void WindowSdl::toggleFullscreen() {
    if (!window) {
        return;
    }
    SDL_WindowFlags window_flags = SDL_GetWindowFlags(window.get());
    bool is_fullscreen = (window_flags & SDL_WINDOW_FULLSCREEN) != 0;
    if (!SDL_SetWindowFullscreen(window.get(), !is_fullscreen)) {
        log_sdl_warning("Failed to toggle fullscreen");
        return;
    }
    sync_window_if_possible(window.get(), "Failed to sync fullscreen toggle");
}

void WindowSdl::setTextInputEnabled(bool enabled)
{
    if (!window) {
        return;
    }
    if (enabled) {
        if (!SDL_StartTextInput(window.get())) {
            LOG(Warning) << "Failed to start SDL text input: " << SDL_GetError();
            SDL_ClearError();
        }
        return;
    }
    if (!SDL_StopTextInput(window.get())) {
        LOG(Warning) << "Failed to stop SDL text input: " << SDL_GetError();
        SDL_ClearError();
    }
}

bool WindowSdl::isTextInputEnabled() const
{
    if (!window) {
        return false;
    }
    return SDL_TextInputActive(window.get());
}

WindowStartupMode WindowSdl::currentStartupMode() const
{
    if (!window) {
        return WindowStartupMode::Windowed;
    }
    SDL_WindowFlags window_flags = SDL_GetWindowFlags(window.get());
    if ((window_flags & SDL_WINDOW_FULLSCREEN) != 0) {
        return WindowStartupMode::Fullscreen;
    }
    if ((window_flags & SDL_WINDOW_MAXIMIZED) != 0) {
        return WindowStartupMode::Maximized;
    }
    return WindowStartupMode::Windowed;
}

bool WindowSdl::getWindowSize(int& out_width, int& out_height) const
{
    if (!window) {
        return false;
    }
    return SDL_GetWindowSize(window.get(), &out_width, &out_height);
}

bool WindowSdl::getWindowSizeInPixels(int& out_width, int& out_height) const
{
    if (!window) {
        return false;
    }
    return SDL_GetWindowSizeInPixels(window.get(), &out_width, &out_height);
}

void WindowSdl::updateViewportFromWindowPixels()
{
    if (!window) {
        return;
    }
    int pixel_width = 0;
    int pixel_height = 0;
    if (!SDL_GetWindowSizeInPixels(window.get(), &pixel_width, &pixel_height)) {
        LOG(Warning) << "Failed to query window pixel size: " << SDL_GetError();
        SDL_ClearError();
        return;
    }
    glViewport(0, 0, pixel_width, pixel_height);
}
