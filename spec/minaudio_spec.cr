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
    MinAudio::VERSION.should eq("0.2.0")
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

  describe MinAudio::AudioBuffer do
    # Fully decoded PCM (f32) living in memory — the sample-loading half
    # of 0.2.0: load once, play many times through Engine#sound(buffer).
    it "decodes a file into PCM" do
      path = "/tmp/minaudio_spec_ab.wav"
      File.write(path, sine_wav(4410))
      begin
        buf = MinAudio::AudioBuffer.from_file(path)
        buf.channels.should eq(1)
        buf.sample_rate.should eq(44100)
        buf.frames.should eq(4410)
        buf.close
        buf.closed?.should be_true
      ensure
        File.delete(path)
      end
    end

    it "decodes in-memory bytes" do
      buf = MinAudio::AudioBuffer.from_memory(sine_wav(2205, 2, 22050))
      buf.channels.should eq(2)
      buf.sample_rate.should eq(22050)
      buf.frames.should eq(2205)
      buf.close
    end

    it "raises on garbage input" do
      expect_raises(MinAudio::Error) do
        MinAudio::AudioBuffer.from_memory(Bytes.new(64) { |i| i.to_u8 })
      end
    end
  end

  describe MinAudio::Capture do
    # The 0.2.0 ring capture (f32, pull model): open → start → poll
    # available_frames → read(buf) → stop → close. Same headless contract
    # as CaptureDevice — without a microphone init fails cleanly.
    it "init fails cleanly without a capture device" do
      devices = MinAudio::Context.devices[:capture]
      if devices.empty?
        expect_raises(MinAudio::Error) do
          MinAudio::Capture.new
        end
        next
      end
      cap = MinAudio::Capture.new(sample_rate: 48_000, channels: 1,
        ring_frames: 16_384)
      begin
        cap.sample_rate.should be > 0
        cap.channels.should eq(1)
        cap.start
        # ALSA & friends can need a few periods before the first frames
        # land — poll for up to 2s instead of a fixed sleep.
        deadline = Time.utc + 2.seconds
        while cap.available_frames == 0 && Time.utc < deadline
          sleep 50.milliseconds
        end
        cap.available_frames.should be > 0
        buf = Bytes.new(4800 * 1 * 4) # room for 4800 f32 frames
        n = cap.read(buf)
        n.should be > 0
        n.should be <= 4800
        cap.available_frames.should be < 16_385 # bounded by the ring
        cap.stop
      ensure
        cap.close
        cap.closed?.should be_true
      end
    end

    it "raises on use after close" do
      devices = MinAudio::Context.devices[:capture]
      next if devices.empty?
      cap = MinAudio::Capture.new
      cap.close
      expect_raises(MinAudio::Error) { cap.start }
    end
  end

  describe MinAudio::CaptureDevice do
    # Capture opens real hardware (and needs permission on mobile) — CI
    # machines have none, so the headless guarantee is only "fails
    # cleanly, never segfaults". With a microphone present (dev box) the
    # full open → start → drain → stop cycle runs.
    it "init fails cleanly without a capture device" do
      devices = MinAudio::Context.devices[:capture]
      if devices.empty?
        expect_raises(MinAudio::Error) do
          MinAudio::CaptureDevice.new
        end
        next
      end
      dev = MinAudio::CaptureDevice.new
      begin
        dev.sample_rate.should eq(16000)
        dev.channels.should eq(1)
        dev.start
        sleep 150.milliseconds
        dev.pending.should be >= 0
        dev.drain.size.should be >= 0
        dev.stop
      ensure
        dev.close
        dev.closed?.should be_true
      end
    end
  end
end
