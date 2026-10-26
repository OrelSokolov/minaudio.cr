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
