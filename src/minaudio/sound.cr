# MinAudio::Sound — one playing (or ready-to-play) sound object, the
# ma_sound wrapper. Created via MinAudio::Engine#play / #sound (never
# initialized directly: the ma_sound memory lives in the object, the
# size coming from ext's minaudio_sizeof_sound).
#
# A Sound MUST NOT outlive its Engine (miniaudio owns the resource
# manager the sound reads through). The Engine tracks the sounds it
# created and uninits them in #close — keep a reference to the engine
# for as long as any Sound exists, or call Engine#stop_all first.

module MinAudio
  class Sound
    # The engine this sound belongs to (kept for #close bookkeeping).
    getter engine : Engine

    # Opaque ma_sound storage; the pointer handed to lib calls.
    @buf : Bytes
    @closed : Bool = false

    # Internal: allocate + ma_sound_init_from_file. Raises MinAudio::Error
    # when the file cannot be opened or decoded.
    def initialize(@engine : Engine, path : String, *,
                   stream : Bool = false, async : Bool = false,
                   group : SoundGroup? = nil, fence : Void* = Pointer(Void).null)
      flags = 0
      flags |= LibMinAudio::SOUND_FLAG_STREAM if stream
      flags |= LibMinAudio::SOUND_FLAG_ASYNC if async
      @buf = Bytes.new(LibMinAudio.sizeof_sound)
      MinAudio.check(
        LibMinAudio.sound_init_from_file(
          engine.to_unsafe, path.to_unsafe, flags.to_u32!,
          group.try(&.to_unsafe) || Pointer(Void).null,
          fence, @buf),
        "init sound #{path.inspect}")
    end

    # Internal: copy of an existing sound (shares the underlying data).
    def initialize(@engine : Engine, existing : Sound, *,
                   group : SoundGroup? = nil)
      @buf = Bytes.new(LibMinAudio.sizeof_sound)
      MinAudio.check(
        LibMinAudio.sound_init_copy(
          engine.to_unsafe, existing.to_unsafe, 0,
          group.try(&.to_unsafe) || Pointer(Void).null, @buf),
        "copy sound")
    end

    def to_unsafe : Void*
      @buf.to_unsafe.as(Void*)
    end

    def closed? : Bool
      @closed
    end

    # Start (or restart after #stop) playback. Idempotent while playing.
    def start : self
      ensure_open
      MinAudio.check(LibMinAudio.sound_start(to_unsafe), "sound start")
      self
    end

    # Stop playback (keeps the sound — #start replays from the cursor).
    def stop : self
      ensure_open
      MinAudio.check(LibMinAudio.sound_stop(to_unsafe), "sound stop")
      self
    end

    # Stop with a fade-out over `fade_ms` milliseconds.
    def stop(fade_ms : Int) : self
      ensure_open
      MinAudio.check(
        LibMinAudio.sound_stop_with_fade_ms(to_unsafe, fade_ms.to_u64!),
        "sound stop (fade)")
      self
    end

    def playing? : Bool
      ensure_open
      LibMinAudio.sound_is_playing(to_unsafe) != 0
    end

    # At the end of its data (a looping sound never is).
    def at_end? : Bool
      ensure_open
      LibMinAudio.sound_at_end(to_unsafe) != 0
    end

    def volume : Float32
      LibMinAudio.sound_get_volume(to_unsafe)
    end

    def volume=(volume : Float32) : Float32
      LibMinAudio.sound_set_volume(to_unsafe, volume)
      volume
    end

    # -1.0 left .. +1.0 right.
    def pan : Float32
      LibMinAudio.sound_get_pan(to_unsafe)
    end

    def pan=(pan : Float32) : Float32
      LibMinAudio.sound_set_pan(to_unsafe, pan.clamp(-1.0f32, 1.0f32))
      pan
    end

    # 1.0 = original, 2.0 = one octave up, 0.5 = one octave down.
    def pitch : Float32
      LibMinAudio.sound_get_pitch(to_unsafe)
    end

    def pitch=(pitch : Float32) : Float32
      LibMinAudio.sound_set_pitch(to_unsafe, pitch)
      pitch
    end

    def looping? : Bool
      LibMinAudio.sound_is_looping(to_unsafe) != 0
    end

    def looping=(loop : Bool) : Bool
      LibMinAudio.sound_set_looping(to_unsafe, loop ? 1 : 0)
      loop
    end

    # Seek to an absolute position in seconds.
    def seek(seconds : Float32) : self
      ensure_open
      MinAudio.check(
        LibMinAudio.sound_seek_to_second(to_unsafe, seconds),
        "sound seek")
      self
    end

    # Current position in seconds.
    def cursor : Float32
      out = uninitialized Float32
      MinAudio.check(
        LibMinAudio.sound_get_cursor_in_seconds(to_unsafe, pointerof(out)),
        "sound cursor")
      out
    end

    # Total duration in seconds (0 when unknown, e.g. a stream).
    def length : Float32
      out = uninitialized Float32
      MinAudio.check(
        LibMinAudio.sound_get_length_in_seconds(to_unsafe, pointerof(out)),
        "sound length")
      out
    end

    # Fade volume from `from` to `to` over `fade_ms`. `from`/`to` of -1
    # mean "the current volume" (miniaudio convention).
    def fade(from : Float32, to : Float32, fade_ms : Int) : Nil
      LibMinAudio.sound_set_fade_in_ms(to_unsafe, from, to, fade_ms.to_u64!)
    end

    # 3D position (spatialization needs engine config flags upstream of
    # this API; harmless without them).
    def position=(pos : {Float32, Float32, Float32}) : Nil
      LibMinAudio.sound_set_position(to_unsafe, pos[0], pos[1], pos[2])
    end

    # An independent copy sharing this sound's decoded data.
    def dup : Sound
      Sound.new(@engine, self)
    end

    # Uninit the underlying ma_sound. Safe to call twice; further port
    # calls on this object raise.
    def close : Nil
      return if @closed
      LibMinAudio.sound_uninit(to_unsafe)
      @closed = true
    end

    def finalize
      close
    end

    private def ensure_open : Nil
      raise Error.new(Result::INVALID_OPERATION, "sound is closed") if @closed
    end
  end
end
