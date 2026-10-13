# MinAudio::Decoder — headless PCM decoding (ma_decoder wrapper): bytes or
# file in, Float32 interleaved frames out. No device needed — this is the
# offline half of the API (analysis, loading samples into memory, tests):
#
#   dec = MinAudio::Decoder.from_file("song.mp3")
#   dec.sample_rate  # => 44100
#   dec.channels     # => 2
#   frames = dec.read(dec.length_frames) # => Bytes, f32 interleaved
#   dec.close
#
# All decoders convert to Float32 on read (config built in ext); pass
# `channels`/`sample_rate` to also resrc/mix, or 0 (default) to keep the
# source format.

module MinAudio
  class Decoder
    @buf : Bytes
    @closed : Bool = false

    # Decode an in-memory file image (WAV/MP3/FLAC — whatever the vendored
    # miniaudio builds decode; Vorbis is off by default).
    def self.from_memory(data : Bytes, *, channels : Int32 = 0,
                         sample_rate : Int32 = 0) : self
      dec = new
      MinAudio.check(
        LibMinAudio.decoder_init_memory_f32(
          data.to_unsafe.as(Void*), data.size,
          channels.to_u32!, sample_rate.to_u32!, dec.@buf),
        "decode memory image")
      dec
    end

    # Decode a file from disk.
    def self.from_file(path : String, *, channels : Int32 = 0,
                       sample_rate : Int32 = 0) : self
      dec = new
      MinAudio.check(
        LibMinAudio.decoder_init_file_f32(
          path.to_unsafe, channels.to_u32!, sample_rate.to_u32!, dec.@buf),
        "decode #{path.inspect}")
      dec
    end

    protected def initialize
      @buf = Bytes.new(LibMinAudio.sizeof_decoder)
    end

    protected def to_unsafe : Void*
      @buf.to_unsafe.as(Void*)
    end

    def closed? : Bool
      @closed
    end

    # Source channels (after the f32 conversion config).
    def channels : UInt32
      ch = uninitialized UInt32
      rate = uninitialized UInt32
      MinAudio.check(
        LibMinAudio.decoder_format(to_unsafe, pointerof(ch), pointerof(rate)),
        "decoder format")
      ch
    end

    def sample_rate : UInt32
      ch = uninitialized UInt32
      rate = uninitialized UInt32
      MinAudio.check(
        LibMinAudio.decoder_format(to_unsafe, pointerof(ch), pointerof(rate)),
        "decoder format")
      rate
    end

    # Total frames (a frame = one sample per channel). 0 when unknown
    # (streams). For MP3 this decodes the whole file — do not call it in
    # a hot loop.
    def length_frames : UInt64
      len = uninitialized UInt64
      MinAudio.check(
        LibMinAudio.decoder_get_length_in_pcm_frames(to_unsafe, pointerof(len)),
        "decoder length")
      len
    end

    def cursor_frames : UInt64
      cur = uninitialized UInt64
      MinAudio.check(
        LibMinAudio.decoder_get_cursor_in_pcm_frames(to_unsafe, pointerof(cur)),
        "decoder cursor")
      cur
    end

    def seek(frame_index : Int) : self
      MinAudio.check(
        LibMinAudio.decoder_seek_to_pcm_frame(to_unsafe, frame_index.to_u64!),
        "decoder seek")
      self
    end

    # Read up to `frame_count` frames as interleaved Float32 samples
    # (frame_count * channels * 4 bytes). Shorter than requested means
    # end of data; empty means done.
    def read(frame_count : Int) : Bytes
      ch = channels
      buf = Bytes.new(frame_count.to_u64! * ch * 4)
      got = uninitialized UInt64
      MinAudio.check(
        LibMinAudio.decoder_read_pcm_frames(
          to_unsafe, buf.to_unsafe, frame_count.to_u64!, pointerof(got)),
        "decoder read")
      got == frame_count.to_u64! ? buf : buf[0, (got * ch * 4).to_i32!]
    end

    # Read every remaining frame (see #length_frames for the caveats).
    def read_all : Bytes
      total = length_frames - cursor_frames
      return Bytes.new(0) if total == 0
      read(total.to_i32!)
    end

    def close : Nil
      return if @closed
      LibMinAudio.decoder_uninit(to_unsafe)
      @closed = true
    end

    def finalize
      close
    end
  end
end
