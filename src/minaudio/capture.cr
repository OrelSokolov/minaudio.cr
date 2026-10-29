# MinAudio::CaptureDevice — microphone capture (ma_device, capture mode).
# The C side (ext/miniaudio.c) runs the device with a data callback that
# appends s16le PCM into a mutex-guarded buffer, so the reader never
# blocks — the audio analog of the camera's latest-frame slot:
#
#   dev = MinAudio::CaptureDevice.new            # default mic, 16 kHz mono
#   dev.start
#   chunk = dev.drain                            # Bytes (s16le), empty when idle
#   dev.stop
#   dev.close
#
# A specific microphone is selected by its opaque id blob from
# `Context.devices[:capture]` (DeviceInfo#id). `backends` pins the
# backend list (LibMinAudio::BACKEND_*), like Engine.new. Errors raise
# MinAudio::Error; permission (RECORD_AUDIO on Android, TCC on macOS) is
# the application's job — without it init fails cleanly.

module MinAudio
  class CaptureDevice
    getter sample_rate : Int32
    getter channels : Int32

    @handle : Pointer(Void)
    @closed : Bool = false

    # `device_id` is an opaque ma_device_id blob from Context.devices
    # (DeviceInfo#id); nil = the default capture device.
    def initialize(device_id : Bytes? = nil, sample_rate : Int32 = 16000,
                   channels : Int32 = 1,
                   backends : Array(Int32)? = nil)
      result = uninitialized Int32
      backends_ptr = Pointer(Int32).null
      backends_count = 0
      if backends && !backends.empty?
        backends_ptr = backends.to_unsafe
        backends_count = backends.size
      end
      @handle = LibMinAudio.capture_new(
        device_id.try(&.to_unsafe) || Pointer(UInt8).null,
        sample_rate, channels, backends_ptr, backends_count,
        pointerof(result))
      if @handle.null?
        raise Error.new(Result.from_value?(result) || Result::ERROR,
          "capture device init (#{backends ? "backends: #{backends.inspect}, " : ""}" \
          "no microphone / permission denied?)")
      end
      @sample_rate = LibMinAudio.capture_rate(@handle)
      @channels = LibMinAudio.capture_channels(@handle)
    end

    def start : self
      ensure_open
      MinAudio.check(LibMinAudio.capture_start(@handle), "capture start")
      self
    end

    def stop : self
      ensure_open
      MinAudio.check(LibMinAudio.capture_stop(@handle), "capture stop")
      self
    end

    # Bytes accumulated since the last drain, s16le PCM (empty slice when
    # nothing new). Never blocks — safe on the UI frame thread.
    def drain : Bytes
      ensure_open
      pending = LibMinAudio.capture_pending(@handle)
      return Bytes.new(0) if pending == 0
      buf = Bytes.new(pending)
      n = LibMinAudio.capture_drain(@handle, buf.to_unsafe, buf.size)
      buf[0, n.to_i32!]
    end

    # Bytes waiting right now (level meters, tests).
    def pending : Int32
      return 0 if @closed
      LibMinAudio.capture_pending(@handle).to_i32!
    end

    def closed? : Bool
      @closed
    end

    # Stop (if running) and free the device. Idempotent.
    def close : Nil
      return if @closed
      LibMinAudio.capture_free(@handle)
      @handle = Pointer(Void).null
      @closed = true
    end

    def finalize
      close
    end

    private def ensure_open : Nil
      raise Error.new(Result::INVALID_OPERATION, "capture device is closed") if @closed
    end
  end
end

# MinAudio::Capture — the 0.2.0 pull-model ring capture (ma_device with a
# data callback appending f32 frames into a FIXED ring of `ring_frames`
# frames; the audio-thread callback never enters Crystal):
#
#   cap = MinAudio::Capture.new                    # 48 kHz mono, 16k ring
#   cap = MinAudio::Capture.new(ring_frames: 8_192)
#   cap.start
#   n = cap.available_frames                       # UInt64 frames waiting
#   buf = Bytes.new(4800 * 1 * 4)                  # room for 4800 f32 frames
#   n = cap.read(buf)                              # frames actually read
#   cap.stop
#   cap.close
#
# read never blocks — call it from the UI frame loop. The ring never
# grows unbounded: when the app reads slower than the mic delivers,
# incoming frames that no longer fit are dropped (the buffered timeline
# keeps its order). Errors raise MinAudio::Error; permission (RECORD_AUDIO
# on Android, TCC on macOS) is the application's job — without it init
# fails cleanly.
module MinAudio
  class Capture
    getter sample_rate : Int32
    getter channels : Int32
    getter ring_frames : Int32

    @handle : Pointer(Void)
    @closed : Bool = false

    # `backends` pins the backend list (LibMinAudio::BACKEND_*), like
    # Engine.new — e.g. [BACKEND_OPENSL, BACKEND_AAUDIO] on Android.
    def initialize(sample_rate : Int32 = 48_000, channels : Int32 = 1,
                   ring_frames : Int32 = 16_384,
                   backends : Array(Int32)? = nil)
      result = uninitialized Int32
      backends_ptr = Pointer(Int32).null
      backends_count = 0
      if backends && !backends.empty?
        backends_ptr = backends.to_unsafe
        backends_count = backends.size
      end
      @handle = LibMinAudio.ring_new(
        sample_rate, channels, ring_frames, backends_ptr, backends_count,
        pointerof(result))
      if @handle.null?
        raise Error.new(Result.from_value?(result) || Result::ERROR,
          "capture init (#{backends ? "backends: #{backends.inspect}, " : ""}" \
          "no microphone / permission denied?)")
      end
      @sample_rate = LibMinAudio.ring_rate(@handle)
      @channels = LibMinAudio.ring_channels(@handle)
      @ring_frames = ring_frames
    end

    def start : self
      ensure_open
      MinAudio.check(LibMinAudio.ring_start(@handle), "capture start")
      self
    end

    def stop : self
      ensure_open
      MinAudio.check(LibMinAudio.ring_stop(@handle), "capture stop")
      self
    end

    # f32-interleaved frames waiting in the ring right now (level meters,
    # sizing the read buffer).
    def available_frames : UInt64
      return 0u64 if @closed
      LibMinAudio.ring_available(@handle)
    end

    # Pull up to buf.size / (channels * 4) frames of interleaved-f32 PCM
    # into `buf`; returns the frame count actually read (0 = nothing
    # captured since the last read). Never blocks.
    def read(buf : Bytes) : Int32
      ensure_open
      max = buf.size // (@channels * 4)
      return 0 if max == 0
      LibMinAudio.ring_read(
        @handle, buf.to_unsafe.as(Float32*), max.to_u64!).to_i32!
    end

    def closed? : Bool
      @closed
    end

    # Stop (if running) and free the device. Idempotent.
    def close : Nil
      return if @closed
      LibMinAudio.ring_free(@handle)
      @handle = Pointer(Void).null
      @closed = true
    end

    def finalize
      close
    end

    private def ensure_open : Nil
      raise Error.new(Result::INVALID_OPERATION, "capture is closed") if @closed
    end
  end
end
