# audio-input

## Canonical Import

```fennel
(local audio-input (require :audio-input))
```

## Source Files

- `src/lua_audio_input.cpp`
- `src/audio_input.h`

## What It Provides

`audio-input` captures microphone/input-device samples into a ring buffer and exposes device enumeration helpers.

## API Summary

- `AudioInput([options])` creates an input stream. Options include `:sample-rate`, `:channels`, `:frames-per-buffer`, `:device`, `:buffer-frames`, and `:buffer-seconds`.
- `list-devices()` returns tables with device `index`, `name`, `max-input-channels`, `default-sample-rate`, `host-api`, and default latency values.
- `default-input-device()` returns the default device index or `nil`.
- `AudioInput` methods include `start`, `stop`, `running?`, `channels`, `sample-rate`, `available-frames`, `read-frames`, `read-frames-into`, `clear`, `dropped-samples`, and `overflow-count`.

## Examples

```fennel
(local audio-input (require :audio-input))

(local input (audio-input.AudioInput {:sample-rate 48000 :channels 1}))
(input:start)
(when (> (input:available-frames) 0)
  (local samples (input:read-frames 256)))
(input:stop)
```

## Errors and Platform Notes

Device availability depends on the host audio stack. `read-frames-into` requires a valid native float buffer pointer and raises if it receives `nil`.

## Related Modules

- [`audio`](/sdk/modules/audio) for playback.
- [`aubio`](/sdk/modules/aubio) for feeding captured samples into analysis buffers.

## Aliases and Search Terms

Search terms: microphone, audio input, capture, PortAudio, device list, samples.
