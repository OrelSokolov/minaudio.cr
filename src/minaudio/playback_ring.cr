# MinAudio::PlaybackRing — push-model playback (ma_device, playback mode)
# over a FIXED ring of `ring_frames` interleaved-f32 frames. The device's
# data callback PULLS from the ring on the audio thread (C only — it never
# enters Crystal); the app thread writes ahead of time from its frame loop:
#
#   ring = MinAudio::PlaybackRing.new(44_100, 2, ring_frames: 44_100)
#   ring.start
#   written = ring.write(pcm_slice)   # frames accepted (0 = full — retry)
#   clock  = ring.consumed_frames     # played frames, silence included
#   ring.stop
#   ring.close
#
# The sync contract for A/V players: on underrun the callback outputs
# SILENCE and consumed still advances, so the device timeline stays
# contiguous — a master clock derived from `consumed_frames` never stalls,
# and the feeder just drops frames that became stale. `write` never
# blocks; it returns how many frames fit, the caller keeps the remainder.
# `clear` drops buffered frames (seek re-positioning) without touching the
# timeline counters.
module MinAudio
  class PlaybackRing
    getter sample_rate : Int32
    getter channels : Int32
    getter ring_frames : Int32

    @handle : Pointer(Void)
    @closed : Bool = false

    # `backends` pins the backend list (LibMinAudio::BACKEND_*), like
    # Engine.new.
    def initialize(sample_rate : Int32, channels : Int32,
                   ring_frames : Int32 = 48_000,
                   backends : Array(Int32)? = nil)
      result = uninitialized Int32
      backends_ptr = Pointer(Int32).null
      backends_count = 0
      if backends && !backends.empty?
        backends_ptr = backends.to_unsafe
        backends_count = backends.size
      end
      @handle = LibMinAudio.pring_new(
        sample_rate, channels, ring_frames, backends_ptr, backends_count,
        pointerof(result))
      if @handle.null?
        raise Error.new(Result.from_value?(result) || Result::ERROR,
          "playback init (#{backends ? "backends: #{backends.inspect}, " : ""}" \
          "no audio device?)")
      end
      @sample_rate = LibMinAudio.pring_rate(@handle)
      @channels = LibMinAudio.pring_channels(@handle)
      @ring_frames = ring_frames
    end

    def start : self
      ensure_open
      MinAudio.check(LibMinAudio.pring_start(@handle), "playback start")
      self
    end

    # Device master volume, 0.0..1.0 (the player bar's volume slider).
    def volume=(v : Float32) : Nil
      ensure_open
      MinAudio.check(LibMinAudio.pring_set_volume(@handle, v.clamp(0.0f32, 1.0f32)),
        "playback volume")
    end

    def stop : self
      ensure_open
      MinAudio.check(LibMinAudio.pring_stop(@handle), "playback stop")
      self
    end

    # Append up to `buf.size / (channels * 4)` interleaved-f32 frames;
    # returns the frame count actually accepted (the ring may be nearly
    # full — keep the remainder and retry on a later frame). Never blocks.
    def write(buf : Bytes) : Int32
      ensure_open
      max = buf.size // (@channels * 4)
      return 0 if max == 0
      LibMinAudio.pring_write(
        @handle, buf.to_unsafe.as(Float32*), max.to_u64!).to_i32!
    end

    # Drop everything buffered (seek). Timeline counters keep running.
    def clear : Nil
      return if @closed
      LibMinAudio.pring_clear(@handle)
    end

    # Frames the device has output so far, INCLUDING underrun silence —
    # the hardware-accurate clock source for A/V sync.
    def consumed_frames : UInt64
      return 0u64 if @closed
      LibMinAudio.pring_consumed(@handle)
    end

    # Frames sitting in the ring right now (feed pacing).
    def buffered_frames : UInt64
      return 0u64 if @closed
      LibMinAudio.pring_buffered(@handle)
    end

    def closed? : Bool
      @closed
    end

    # Stop (if running) and free the device. Idempotent.
    def close : Nil
      return if @closed
      LibMinAudio.pring_free(@handle)
      @handle = Pointer(Void).null
      @closed = true
    end

    def finalize
      close
    end

    private def ensure_open : Nil
      raise Error.new(Result::INVALID_OPERATION, "playback ring is closed") if @closed
    end
  end
end
