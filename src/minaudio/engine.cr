# MinAudio::Engine — the ma_engine wrapper: one playback device + the
# resource manager. This is the entry point of the playback API:
#
#   engine = MinAudio::Engine.new
#   click  = engine.sound("click.wav")   # prepared, not started
#   music  = engine.play("music.ogg", loop: true)
#   music.volume = 0.6f32
#   engine.stop_all
#   engine.close
#
# Engine#new opens the default playback device and raises MinAudio::Error
# when no audio device exists (headless CI, no sound card). All sounds
# created through the engine are uninited by #close / the finalizer.

module MinAudio
  class Engine
    @buf : Bytes
    @ctx : Pointer(Void)? # backend-pinned context (nil = default init)
    @closed : Bool = false
    @sounds = [] of Sound
    @groups = [] of SoundGroup

    # `backends` pins the backend list (LibMinAudio::BACKEND_* — e.g.
    # [BACKEND_OPENSL] to bypass AAudio on a vendor build that refuses
    # it). Nil = miniaudio's default priority order.
    def initialize(backends : Array(Int32)? = nil)
      @buf = Bytes.new(LibMinAudio.sizeof_engine)
      if backends
        unless backends.empty?
          ctx = Pointer(Void).null
          MinAudio.check(
            LibMinAudio.context_create(backends.to_unsafe,
              backends.size, pointerof(ctx)),
            "context init (backends: #{backends.inspect})")
          @ctx = ctx
          begin
            MinAudio.check(
              LibMinAudio.engine_init_ctx(ctx, @buf),
              "engine init (backends: #{backends.inspect})")
          rescue ex
            LibMinAudio.context_free(ctx)
            @ctx = nil
            raise ex
          end
        else
          MinAudio.check(
            LibMinAudio.engine_init(Pointer(Void).null, @buf),
            "engine init")
        end
      else
        MinAudio.check(
          LibMinAudio.engine_init(Pointer(Void).null, @buf),
          "engine init (no playback device?)")
      end
    end

    def to_unsafe : Void*
      @buf.to_unsafe.as(Void*)
    end

    def closed? : Bool
      @closed
    end

    # Master volume applied to every sound (also see Sound#volume=).
    def volume : Float32
      LibMinAudio.engine_get_volume(to_unsafe)
    end

    def volume=(volume : Float32) : Float32
      LibMinAudio.engine_set_volume(to_unsafe, volume)
      volume
    end

    # Temporarily silence everything (device-level; sounds keep state).
    def pause : self
      MinAudio.check(LibMinAudio.engine_stop(to_unsafe), "engine pause")
      self
    end

    def resume : self
      MinAudio.check(LibMinAudio.engine_start(to_unsafe), "engine resume")
      self
    end

    # Output channels / sample rate of the opened device.
    def channels : UInt32
      LibMinAudio.engine_get_channels(to_unsafe)
    end

    def sample_rate : UInt32
      LibMinAudio.engine_get_sample_rate(to_unsafe)
    end

    # Fire-and-forget playback: miniaudio loads, plays and reaps the
    # sound itself — no Sound object comes back. Ideal for UI clicks.
    def play_file(path : String, group : SoundGroup? = nil) : Nil
      ensure_open
      MinAudio.check(
        LibMinAudio.engine_play_sound(
          to_unsafe, path.to_unsafe,
          group.try(&.to_unsafe) || Pointer(Void).null),
        "play #{path.inspect}")
    end

    # Prepare a sound without starting it (Sound#start when wanted).
    def sound(path : String, *, stream : Bool = false,
              async : Bool = false, group : SoundGroup? = nil) : Sound
      ensure_open
      Sound.new(self, path, stream: stream, async: async, group: group)
        .tap { |s| track(s) }
    end

    # Prepare a sound from a decoded in-memory AudioBuffer (see
    # AudioBuffer) without starting it. The buffer must outlive the
    # sound — the Sound keeps it referenced, and Engine#close closes
    # tracked sounds before the buffer is expected to go.
    def sound(buffer : AudioBuffer, *, group : SoundGroup? = nil) : Sound
      ensure_open
      Sound.new(self, buffer, group: group).tap { |s| track(s) }
    end

    # Prepare and immediately start a sound. `loop` keeps it looping.
    def play(path : String, *, volume : Float32? = nil, loop : Bool = false,
             stream : Bool = false, group : SoundGroup? = nil) : Sound
      s = sound(path, stream: stream, group: group)
      s.looping = true if loop
      s.volume = volume unless volume.nil?
      s.start
    end

    # Stop (not uninit) every tracked sound.
    def stop_all : Nil
      @sounds.each { |s| s.stop unless s.closed? }
    end

    # A named volume/stop bus (ma_sound_group). Sounds pass `group:`
    # at creation; the master group is used when nil.
    def group(parent : SoundGroup? = nil) : SoundGroup
      ensure_open
      SoundGroup.new(self, parent).tap { |g| @groups << g }
    end

    # Uninit every tracked sound and the engine itself. Idempotent.
    # The pinned context (if any) is freed AFTER the engine — miniaudio
    # keeps the pointer.
    def close : Nil
      return if @closed
      @sounds.each(&.close)
      @groups.each(&.close)
      LibMinAudio.engine_uninit(to_unsafe)
      if (ctx = @ctx)
        LibMinAudio.context_free(ctx)
        @ctx = nil
      end
      @closed = true
    end

    def finalize
      close
    end

    private def track(sound : Sound) : Nil
      # Drop finished sounds so a long session does not accumulate them.
      @sounds.reject! { |s| s.closed? || (!s.looping? && s.at_end?) }
      @sounds << sound
    end

    private def ensure_open : Nil
      raise Error.new(Result::INVALID_OPERATION, "engine is closed") if @closed
    end
  end
end
