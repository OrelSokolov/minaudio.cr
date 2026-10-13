# MinAudio::SoundGroup — ma_sound_group wrapper: a volume/stop bus.
# Sounds attach at creation (Engine#play(..., group: g)); stopping or
# fading the group hits every attached sound at once.

module MinAudio
  class SoundGroup
    getter engine : Engine
    @buf : Bytes
    @closed : Bool = false

    # Internal: use Engine#group.
    def initialize(@engine : Engine, parent : SoundGroup?)
      @buf = Bytes.new(LibMinAudio.sizeof_sound_group)
      MinAudio.check(
        LibMinAudio.group_init(
          engine.to_unsafe, 0,
          parent.try(&.to_unsafe) || Pointer(Void).null, @buf),
        "group init")
    end

    def to_unsafe : Void*
      @buf.to_unsafe.as(Void*)
    end

    def closed? : Bool
      @closed
    end

    def start : self
      ensure_open
      MinAudio.check(LibMinAudio.group_start(to_unsafe), "group start")
      self
    end

    def stop : self
      ensure_open
      MinAudio.check(LibMinAudio.group_stop(to_unsafe), "group stop")
      self
    end

    def volume : Float32
      LibMinAudio.group_get_volume(to_unsafe)
    end

    def volume=(volume : Float32) : Float32
      LibMinAudio.group_set_volume(to_unsafe, volume)
      volume
    end

    def close : Nil
      return if @closed
      LibMinAudio.group_uninit(to_unsafe)
      @closed = true
    end

    def finalize
      close
    end

    private def ensure_open : Nil
      raise Error.new(Result::INVALID_OPERATION, "group is closed") if @closed
    end
  end
end
