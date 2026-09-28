# audio

## Canonical Import

```fennel
(local audio (require :audio))
```

## Source Files

- `src/lua_audio.cpp`
- `src/audio.h`

## What It Provides

`audio` exposes the native `Audio` usertype for sound loading, playback, listener/source controls, master volume, and update/reset integration.

## API Summary

- `Audio` methods include `loadSound`, `loadSoundAsync`, `unloadSound`, `playSound`, `stopSound`, `waitForSoundToFinish`, `isReady`, `reset`, and `update`.
- Listener controls: `setListenerPosition`, `setListenerOrientation`, and `setListenerVelocity`.
- Source controls: `setSourcePosition` and `setSourceVelocity`.
- Volume controls: `setMasterVolume` and `getMasterVolume`.
- `playSound(name position [loop?] [positional?])` returns the native source handle/id used by source controls.

## Examples

```fennel
(local audio (require :audio))
(local glm (require :glm))

(fn play-click [audio-device]
  (audio-device:loadSound :click "assets/audio/click.wav")
  (when (audio-device:isReady :click)
    (audio-device:playSound :click (glm.vec3 0 0 0) false false)))
```

## Errors and Platform Notes

This module exports the `Audio` usertype; the runtime owns/provides actual audio instances. `loadSoundAsync` returns `false` and queues the callback when the audio backend is unavailable. CLI tests commonly disable audio to avoid host device warnings.

## Related Modules

- [`audio-input`](/sdk/modules/audio-input) for microphone capture.
- [`aubio`](/sdk/modules/aubio) for audio analysis helpers.
- [`video`](/sdk/modules/video) for video playback audio integration.

## Aliases and Search Terms

Search terms: audio, sound, OpenAL, playback, listener, source, volume, positional audio.
