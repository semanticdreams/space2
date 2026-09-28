# aubio

## Canonical Import

```fennel
(local aubio-vec (require :aubio/vec))
```

## Source Files

- `src/lua_aubio.cpp`
- `src/lua_aubio_vec.cpp`
- `src/lua_aubio_spectral.cpp`
- `src/lua_aubio_temporal.cpp`
- `src/lua_aubio_io.cpp`
- `src/lua_aubio_synth.cpp`
- `src/lua_aubio_utils.cpp`
- `assets/lua/tests/test-aubio.fnl`
- `assets/lua/tests/test-aubio-helpers.fnl`
- `assets/lua/tests/test-aubio-pipelines.fnl`
- `assets/lua/tests/test-aubio-stream.fnl`

## What It Provides

The aubio bindings are exposed as a family of canonical submodules for audio vectors, spectral processing, temporal analysis, audio file IO, synthesis, and utility helpers.

## API Summary

- Canonical submodules: `aubio/vec`, `aubio/spectral`, `aubio/temporal`, `aubio/io`, `aubio/synth`, and `aubio/utils`.
- `aubio/vec` provides `FVec`, `CVec`, `FMat`, `LVec`, vector math/statistics, thresholds, peak picking, autocorrelation, mixdown, and normalization helpers.
- `aubio/spectral` provides `FFT`, `DCT`, `PVoc`, `Filterbank`, `MFCC`, `SpecDesc`, `SpectralWhitening`, and `TSS`.
- `aubio/temporal` provides `Pitch`, `Onset`, `Tempo`, `Notes`, `Resampler`, `Filter`, `FilterBiquad`, `FilterAWeighting`, and `FilterCWeighting`.
- `aubio/io` provides `Source` and `Sink`.
- `aubio/synth` provides `Sampler` and `Wavetable`.
- `aubio/utils` provides `Parameter`, `Scale`, `Hist`, log hooks, `audio-input-into-fvec`, `window`, frequency/MIDI/bin/mel conversions, `unwrap2pi`, and `cleanup`.

## Examples

```fennel
(local aubio-vec (require :aubio/vec))
(local aubio-temporal (require :aubio/temporal))

(local samples (aubio-vec.FVec 1024))
(local pitch (aubio-temporal.Pitch :yin 1024 512 48000))
;; Fill samples from audio input or a file source before running temporal analysis.
```

## Errors and Platform Notes

Constructors and processing methods follow aubio's native size, method-name, sample-rate, and buffer constraints. Pair matching buffer and hop sizes across vector, spectral, temporal, and IO modules.

## Related Modules

- [`audio-input`](/sdk/modules/audio-input) for live capture feeding aubio buffers.
- [`audio`](/sdk/modules/audio) for playback.

## Aliases and Search Terms

Search terms: aubio, aubio/vec, aubio/spectral, aubio/temporal, aubio/io, aubio/synth, aubio/utils, pitch, onset, tempo, FFT, MFCC.
