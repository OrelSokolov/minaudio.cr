# Engine smoke-test: real playback device, generated sine WAV.
require "../src/minaudio"

le = IO::ByteFormat::LittleEndian
rate = 44100
frames = rate # 1 second
wav = Bytes.new(44 + frames * 2)
"RIFF".each_char_with_index { |c, i| wav[i] = c.ord.to_u8 }
le.encode((36 + frames * 2).to_u32, wav[4, 4])
"WAVE".each_char_with_index { |c, i| wav[8 + i] = c.ord.to_u8 }
"fmt ".each_char_with_index { |c, i| wav[12 + i] = c.ord.to_u8 }
le.encode(16u16, wav[16, 2]); le.encode(1u16, wav[20, 2])
le.encode(1u16, wav[22, 2]); le.encode(rate.to_u32!, wav[24, 4])
le.encode((rate * 2).to_u32!, wav[28, 4]); le.encode(2u16, wav[32, 2])
le.encode(16u16, wav[34, 2])
"data".each_char_with_index { |c, i| wav[36 + i] = c.ord.to_u8 }
le.encode((frames * 2).to_u32, wav[40, 4])
frames.times do |f|
  le.encode((Math.sin(f * 2 * Math::PI * 440 / rate) * 8000).to_i16!,
    wav[44 + f * 2, 2])
end
File.write("/tmp/minaudio_smoke.wav", wav)

engine = MinAudio::Engine.new
puts "engine: #{engine.channels}ch @ #{engine.sample_rate}Hz"
puts "playback devices: #{MinAudio::Context.names.inspect}"
s = engine.play("/tmp/minaudio_smoke.wav")
puts "playing=#{s.playing?} len=#{s.length}"
sleep 300.milliseconds
puts "cursor≈#{s.cursor}"
engine.stop_all
engine.close
puts "SMOKE OK"
