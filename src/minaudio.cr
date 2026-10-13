# minaudio.cr — Crystal bindings for miniaudio (https://miniaud.io),
# vendored at v0.11.22 (public domain / MIT-0). Idiomatic wrapper:
#
#   require "minaudio"
#
#   engine = MinAudio::Engine.new
#   engine.play_file("click.wav")              # fire and forget
#   music = engine.play("music.ogg", loop: true)
#   music.volume = 0.5f32
#   engine.stop_all
#
# Headless decoding (no device needed):
#
#   dec = MinAudio::Decoder.from_file("song.mp3")
#   pcm = dec.read_all # Float32 interleaved
#
# Run `rake build` once after install to compile vendor/miniaudio.h into
# lib/libminaudio.a (see README).

require "./minaudio/lib"
require "./minaudio/result"
require "./minaudio/engine"
require "./minaudio/sound"
require "./minaudio/sound_group"
require "./minaudio/decoder"
require "./minaudio/devices"

module MinAudio
  VERSION = "0.1.1"
end
