require "spec"
require "../src/minaudio"

# Headless spec: everything here runs without an audio device. The
# Engine/Context paths open real hardware — they are exercised in the
# README quickstart / the egui.cr demo, not in CI.

# Builds a small in-memory WAV (16-bit PCM sine) the decoders can chew.
def sine_wav(frames : Int32, channels : Int32 = 1,
             rate : Int32 = 44100) : Bytes
  le = IO::ByteFormat::LittleEndian
  data_bytes = frames * channels * 2
  wav = Bytes.new(44 + data_bytes)
  "RIFF".each_char_with_index { |c, i| wav[i] = c.ord.to_u8 }
  le.encode((36 + data_bytes).to_u32, wav[4, 4])
  "WAVE".each_char_with_index { |c, i| wav[8 + i] = c.ord.to_u8 }
  "fmt ".each_char_with_index { |c, i| wav[12 + i] = c.ord.to_u8 }
  le.encode(16u16, wav[16, 2])
  le.encode(1u16, wav[20, 2])                 # PCM
  le.encode(channels.to_u16!, wav[22, 2])
  le.encode(rate.to_u32!, wav[24, 4])
  le.encode((rate * channels * 2).to_u32!, wav[28, 4])
  le.encode((channels * 2).to_u16!, wav[32, 2])
  le.encode(16u16, wav[34, 2])
  "data".each_char_with_index { |c, i| wav[36 + i] = c.ord.to_u8 }
  le.encode(data_bytes.to_u32!, wav[40, 4])
  frames.times do |frame|
    sample = (Math.sin(frame * 2 * Math::PI * 440 / rate) * 8000).to_i16!
    channels.times do |ch|
      le.encode(sample, wav[44 + (frame * channels + ch) * 2, 2])
    end
  end
  wav
end

describe MinAudio do
  it "exposes the vendored version" do
    MinAudio::VERSION.should eq("0.1.0")
  end

  it "maps ma_result codes" do
    MinAudio::Result.from_value(0).should eq(MinAudio::Result::SUCCESS)
    MinAudio::Result.from_value(-10).should eq(MinAudio::Result::INVALID_FILE)
    MinAudio.check(0, "noop").should eq(0)
    expect_raises(MinAudio::Error, /invalid file/) do
      MinAudio.check(-10, "boom")
    end
  end

  describe MinAudio::Decoder do
    it "decodes an in-memory WAV to f32" do
      dec = MinAudio::Decoder.from_memory(sine_wav(1000))
      dec.channels.should eq(1)
      dec.sample_rate.should eq(44100)
      dec.length_frames.should eq(1000)
      pcm = dec.read(500)
      pcm.size.should eq(500 * 1 * 4)
      first = pcm.to_unsafe.as(Float32*)[0]
      first.should be_close(0.0f32, 0.01f32) # sine starts at zero
      dec.read_all.size.should eq(500 * 4)   # the second half
      dec.close
      dec.closed?.should be_true
    end

    it "resamples on request" do
      dec = MinAudio::Decoder.from_memory(sine_wav(44100),
        sample_rate: 22050)
      dec.sample_rate.should eq(22050)
      dec.length_frames.should be_close(22050, 100)
      dec.close
    end

    it "decodes from a file path" do
      path = "/tmp/minaudio_spec.wav"
      File.write(path, sine_wav(4410))
      begin
        dec = MinAudio::Decoder.from_file(path)
        dec.length_frames.should eq(4410)
        dec.close
      ensure
        File.delete(path)
      end
    end

    it "raises on garbage input" do
      expect_raises(MinAudio::Error) do
        MinAudio::Decoder.from_memory(Bytes.new(64) { |i| i.to_u8 })
      end
    end
  end
end
