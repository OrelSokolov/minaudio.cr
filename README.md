# minaudio.cr

Crystal bindings for [miniaudio](https://miniaud.io) — single-header C
audio playback and decoding, wrapped in a typed, idiomatic Crystal API.
The C library is vendored (`vendor/miniaudio.h`, v0.11.22, public domain
/ MIT-0), so nothing is installed system-wide.

## What's covered

| Area | API |
|---|---|
| Playback engine | `MinAudio::Engine` — default device, master volume, pause/resume, fire-and-forget `#play_file` |
| Sounds | `MinAudio::Sound` — start/stop (+fade), volume, pan, pitch, loop, seek/cursor/length, fades, 3D position |
| Groups | `MinAudio::SoundGroup` — volume/stop buses |
| Decoding | `MinAudio::Decoder` — headless WAV/MP3/FLAC → Float32 PCM from file or memory, with optional resample/mix-down |
| Devices | `MinAudio::Context` — playback/capture enumeration (names + opaque ids) |
| Capture | `MinAudio::CaptureDevice` — microphone recording to s16le PCM, non-blocking `#drain` (callback + locked buffer in ext/miniaudio.c) |
| Errors | `MinAudio::Error` carrying a `MinAudio::Result` code (full ma_result table) |

Not wrapped (yet): raw custom `ma_device` playback callbacks, the
node graph, the resource-manager internals, Vorbis (miniaudio default
off), encoders (`MA_NO_ENCODING`).

## Quickstart

```bash
rake build   # compile vendor C → lib/libminaudio.a
rake spec    # headless decoder specs
```

```crystal
require "minaudio"

engine = MinAudio::Engine.new
engine.play_file("click.wav")                     # fire and forget

music = engine.play("music.ogg", loop: true)
music.volume = 0.6f32
music.fade(music.volume, 0.0f32, 1500)            # fade out
music.stop

engine.stop_all
engine.close
```

Headless decoding (no audio device needed):

```crystal
dec = MinAudio::Decoder.from_file("song.mp3")
dec.sample_rate    # => 44100
dec.channels       # => 2
pcm = dec.read_all # => Bytes, interleaved Float32
```

Device enumeration:

```crystal
MinAudio::Context.names.each { |n| puts n }       # playback devices
```

Microphone capture (permission — RECORD_AUDIO on Android, TCC on macOS —
is the application's job; without it init fails cleanly):

```crystal
mic = MinAudio::CaptureDevice.new                  # default mic, 16 kHz mono s16
mic.start
chunk = mic.drain                                  # Bytes of NEW PCM, never blocks
mic.stop
mic.close
# a specific microphone: Context.devices[:capture][i].id → CaptureDevice.new(id)
```

## Integrating into an app

1. Add the shard:

   ```yaml
   dependencies:
     minaudio:
       git: git@github.com:OrelSokolov/minaudio.cr.git
   ```

2. After `shards install`, build the vendored C once:

   ```bash
   (cd lib/minaudio && rake build)
   ```

3. Link with the shard's `lib/` dir, e.g.:

   ```bash
   crystal build src/app.cr --link-flags "-Llib/minaudio/lib"
   ```

Platform libraries and frameworks (CoreAudio/AudioToolbox on macOS,
pthread/dl/m on Linux) are attached by `@[Link]` attributes in
`src/minaudio/lib.cr` — nothing extra to declare.

Windows: build the shard with the MSVC environment available (the
Rakefile shells out to `cl.exe`, matching Crystal's windows-msvc
binaries with `/MD`).

### Android

miniaudio's Android backends are AAudio (default) and OpenSL ES
(fallback); `src/minaudio/lib.cr` links both (`@[Link("aaudio")` +
`@[Link("OpenSLES")]`) when compiled with `flag?(:android)`.

```bash
rake build:android        # → ext/miniaudio_android.o (NDK clang)
# pass it as an extra .o to the APK link, e.g. egui.cr:
#   tmp/android/build_apk.sh app.o sokol_shim_android.o \
#     android_native_app_glue.o nanosvg_shim.o lib/minaudio/ext/miniaudio_android.o
```

The link line needs `-laaudio -lOpenSLES` (mirroring the @[Link]s —
cross-compiled Crystal objects don't carry them).

### iOS

The iOS backend is CoreAudio; the vendored header pulls AVFoundation
(ObjC) there, so the unit compiles as Objective-C:

```bash
rake build:ios             # both → ext/miniaudio_ios_{sim,device}.o
TARGET=sim rake build:ios  # one of them
```

Link the matching object into the app and add the CoreAudio /
AudioToolbox / CoreFoundation frameworks (the darwin branch of lib.cr's
@[Link]s already names them for Crystal-side compilation).

## Layout

```
vendor/miniaudio.h   vendored miniaudio (v0.11.22)
ext/miniaudio.c      MINIAUDIO_IMPLEMENTATION + sizeof/config helpers
src/minaudio/lib.cr  raw FFI bindings (all structs opaque)
src/minaudio/*.cr    Engine, Sound, SoundGroup, Decoder, Context, Result
spec/                headless specs (decoder round-trips)
```

## License

MIT (see `LICENSE`). The vendored miniaudio is public domain / MIT-0
(see `vendor/miniaudio-LICENSE`).
