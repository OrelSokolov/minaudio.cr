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
| Audio buffers | `MinAudio::AudioBuffer` — decode once into in-memory f32 PCM, play any number of sounds off it (`Engine#sound(buffer)`) |
| Groups | `MinAudio::SoundGroup` — volume/stop buses |
| Decoding | `MinAudio::Decoder` — headless WAV/MP3/FLAC → Float32 PCM from file or memory, with optional resample/mix-down |
| Devices | `MinAudio::Context` — playback/capture enumeration (names + opaque ids) |
| Capture | `MinAudio::Capture` — pull-model ring capture (f32, bounded `ring_frames`), non-blocking `#read`/`#available_frames` |
| Capture (legacy) | `MinAudio::CaptureDevice` — 0.1.x s16le capture with unbounded `#drain` |
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

Samples: decode once, replay cheap (also headless — decode only):

```crystal
buf = MinAudio::AudioBuffer.from_file("click.wav") # or from_memory(bytes)
click = engine.sound(buf)   # prepared; start / loop / volume like any Sound
buf.close                   # after the last sound using it is done
```

Device enumeration:

```crystal
MinAudio::Context.names.each { |n| puts n }       # playback devices
```

Microphone capture (pull model; permission — RECORD_AUDIO on Android,
TCC on macOS — is the application's job; without it init fails cleanly):

```crystal
mic = MinAudio::Capture.new                 # 48 kHz mono f32, 16k-frame ring
mic.start
n = mic.available_frames                    # UInt64 frames waiting
buf = Bytes.new(4800 * 1 * 4)               # room for 4800 f32 frames
n = mic.read(buf)                           # frames read, never blocks
mic.stop
mic.close
# the ring never grows: incoming frames that no longer fit are dropped
# (0.1.x CaptureDevice — s16 + unbounded #drain — is still available)
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
src/minaudio/*.cr    Engine, Sound, SoundGroup, AudioBuffer, Decoder, Context, Capture, Result
spec/                headless specs (decoder/buffer round-trips; capture
                     cycle runs when a microphone exists)
```

## License

MIT (see `LICENSE`). The vendored miniaudio is public domain / MIT-0
(see `vendor/miniaudio-LICENSE`).
