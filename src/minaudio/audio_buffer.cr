# MinAudio::AudioBuffer — fully decoded in-memory PCM (f32 interleaved)
# wrapped in an ma_audio_buffer: the sample-loading half of the playback
# API. Decode a file ONCE, then play it any number of times through
# Engine#sound(buffer) — no per-playback file I/O or re-decode, and
# loading works headless (decode only, no playback device opened):
#
#   buf = MinAudio::AudioBuffer.from_file("click.wav")
#   buf.channels     # => 1
#   buf.sample_rate  # => 44100
#   buf.frames       # => 4410
#   sound = engine.sound(buf)  # prepared, not started
#   buf.close                 # after the last sound using it is done
#
# The PCM lives in the buffer object: every Sound created from it reads
# the same memory, so the buffer MUST outlive those sounds — stop and
# close them first (Engine tracks the sounds it created and does this in
# Engine#close; a Sound created from a buffer also keeps it referenced).

module MinAudio
  class AudioBuffer
    getter sample_rate : Int32
    getter channels : Int32

    @handle : Pointer(Void)
    @closed : Bool = false

    # Decode a file from disk (WAV/MP3/FLAC — whatever the vendored
    # miniaudio builds decode; Vorbis is off by default). Raises
    # MinAudio::Error on unreadable/undecodable input.
    def self.from_file(path : String) : self
      result = uninitialized Int32
      handle = LibMinAudio.audio_buffer_new_from_file(
        path.to_unsafe, pointerof(result))
      if handle.null?
        raise Error.new(Result.from_value?(result) || Result::ERROR,
          "decode #{path.inspect}")
      end
      new(handle)
    end

    # Decode an in-memory file image (Bytes, e.g. an asset embedded in
    # the binary).
    def self.from_memory(data : Bytes) : self
      result = uninitialized Int32
      handle = LibMinAudio.audio_buffer_new(
        data.to_unsafe.as(Void*), data.size, pointerof(result))
      if handle.null?
        raise Error.new(Result.from_value?(result) || Result::ERROR,
          "decode memory image")
      end
      new(handle)
    end

    # Internal: wrap an opaque C-side buffer (the constructors above).
    def initialize(@handle : Pointer(Void))
      @sample_rate = LibMinAudio.audio_buffer_rate(@handle).to_i32!
      @channels = LibMinAudio.audio_buffer_channels(@handle).to_i32!
    end

    # Internal: the ma_audio_buffer pointer (Sound init).
    def to_unsafe : Void*
      @handle
    end

    # Total frames (a frame = one sample per channel).
    def frames : UInt64
      ensure_open
      LibMinAudio.audio_buffer_frames(@handle)
    end

    def closed? : Bool
      @closed
    end

    # Free the decoded PCM. Idempotent — but every Sound playing through
    # this buffer must be stopped/closed first (a live Sound reading
    # freed memory would crash the audio thread).
    def close : Nil
      return if @closed
      LibMinAudio.audio_buffer_free(@handle)
      @handle = Pointer(Void).null
      @closed = true
    end

    def finalize
      close
    end

    private def ensure_open : Nil
      raise Error.new(Result::INVALID_OPERATION, "audio buffer is closed") if @closed
    end
  end
end
