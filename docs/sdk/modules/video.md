# video

## Canonical Import

```fennel
(local video (require :video))
```

## Source Files

- `src/lua_video.cpp`
- `src/video_player.h`

## What It Provides

`video` provides video playback through `VideoPlayer` when Space is built with FFmpeg support.

## API Summary

- `available` is true when FFmpeg-backed video support is compiled in; otherwise `missing-reason` explains why playback is unavailable.
- `VideoPlayer(options)` requires `:path` and accepts playback/audio options such as `:loop`, `:autoplay`, `:muted`, `:positional-audio`, `:audio-position`, velocity/direction, gain, pitch, distance, rolloff, reference distance, gain bounds, and cone settings.
- `VideoPlayer` methods include `play`, `pause`, `stop`, `seek`, `update`, `drop`, `ready`, `ended`, `playing`, `status`, `duration`, `position`, `last_error`, `set-positional-audio`, `positional-audio`, `set-audio-position`, and `texture`.

## Examples

```fennel
(local video (require :video))

(when video.available
  (local player (video.VideoPlayer {:path "assets/videos/intro.mp4" :autoplay true}))
  (player:update)
  (when (player:ready)
    (local frame-texture (player:texture))))
```

## Errors and Platform Notes

When FFmpeg support is not built in, `VideoPlayer` raises an error telling you to build with `SPACE_ENABLE_FFMPEG` and install FFmpeg development packages. `VideoPlayer` requires a non-empty `:path` in its options table.

## Related Modules

- [`textures`](/sdk/modules/textures) for consuming the current video frame texture.
- [`audio`](/sdk/modules/audio) for audio device reset interactions and positional playback.

## Aliases and Search Terms

Search terms: video, FFmpeg, media playback, movie, frame texture, positional audio.
