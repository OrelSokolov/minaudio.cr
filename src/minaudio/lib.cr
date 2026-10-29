# Raw FFI surface over miniaudio (vendor/miniaudio.h, v0.11.22) plus the
# ext/miniaudio.c helpers. Structs are deliberately NOT mirrored: every
# miniaudio type is opaque (`Void`) because all of them are initialized
# into caller-allocated memory whose size comes from the minaudio_sizeof_*
# helpers. Value-struct returns (configs) are avoided via the f32 decoder
# helpers. Signatures below were checked against the vendored header.

@[Link("minaudio")]
{% if flag?(:darwin) %}
  # miniaudio's CoreAudio backend (link order: the archive resolves these).
  @[Link(framework: "CoreAudio")]
  @[Link(framework: "AudioToolbox")]
  @[Link(framework: "CoreFoundation")]
{% end %}
{% if flag?(:android) %}
  # miniaudio's Android backends: AAudio (API 26+, default pick) with
  # OpenSL ES as the pre-26 fallback (egui.cr's minSdk 28 always has
  # AAudio; OEM breakage makes the fallback worth linking anyway).
  @[Link("aaudio")]
  @[Link("OpenSLES")]
  @[Link("log")]
{% end %}
{% if flag?(:linux) && !flag?(:android) %}
  @[Link("pthread")]
  @[Link("dl")]
  @[Link("m")]
{% end %}

lib LibMinAudio
  alias SizeT = LibC::SizeT

  # ---- ext helpers (opaque sizes + value-struct avoidance) ------------
  fun sizeof_engine = minaudio_sizeof_engine : SizeT
  fun sizeof_sound = minaudio_sizeof_sound : SizeT
  fun sizeof_decoder = minaudio_sizeof_decoder : SizeT
  fun sizeof_context = minaudio_sizeof_context : SizeT
  fun sizeof_sound_group = minaudio_sizeof_sound_group : SizeT
  fun sizeof_device_id = minaudio_sizeof_device_id : SizeT

  fun decoder_init_memory_f32 = minaudio_decoder_init_memory_f32(
    data : Void*, size : SizeT, channels : UInt32, rate : UInt32,
    dec : Void*
  ) : Int32
  fun decoder_init_file_f32 = minaudio_decoder_init_file_f32(
    path : UInt8*, channels : UInt32, rate : UInt32, dec : Void*
  ) : Int32
  fun decoder_format = minaudio_decoder_format(
    dec : Void*, channels : UInt32*, rate : UInt32*
  ) : Int32

  fun device_info_name = minaudio_device_info_name(info : Void*) : UInt8*
  fun device_info_id_copy = minaudio_device_info_id_copy(
    info : Void*, out : UInt8*
  ) : Void

  # Backend-pinned engine init (see ext): context created with an
  # explicit backend list, engine attached to it. The context outlives
  # the engine — free with context_free AFTER engine_uninit.
  fun context_create = minaudio_context_create(
    backends : Int32*, count : Int32, out_ctx : Void**
  ) : Int32
  fun context_free = minaudio_context_free(ctx : Void*) : Void
  fun engine_init_ctx = minaudio_engine_init_ctx(ctx : Void*, engine : Void*) : Int32

  # ---- ext capture helpers (see ext/miniaudio.c) ----------------------
  # Opaque per-device capture state: the device runs with a data callback
  # appending s16 PCM to a locked buffer; drain is non-blocking for the
  # UI frame thread. capture_new leaves the device STOPPED — call
  # capture_start explicitly. Free with capture_free.
  fun capture_new = minaudio_capture_new(
    device_id : UInt8*, rate : Int32, channels : Int32,
    backends : Int32*, backend_count : Int32, out_result : Int32*
  ) : Void*
  fun capture_start = minaudio_capture_start(cap : Void*) : Int32
  fun capture_stop = minaudio_capture_stop(cap : Void*) : Int32
  fun capture_drain = minaudio_capture_drain(
    cap : Void*, out : UInt8*, cap_len : SizeT
  ) : SizeT
  fun capture_pending = minaudio_capture_pending(cap : Void*) : SizeT
  fun capture_rate = minaudio_capture_rate(cap : Void*) : Int32
  fun capture_channels = minaudio_capture_channels(cap : Void*) : Int32
  fun capture_free = minaudio_capture_free(cap : Void*) : Void

  # ---- ext audio-buffer helpers (0.2.0) --------------------------------
  # Fully decoded in-memory PCM (f32 interleaved) wrapped in an
  # ma_audio_buffer: decode once with audio_buffer_new / _new_from_file,
  # play any number of sounds off it (see sound_init_from_audio_buffer
  # below), free with audio_buffer_free AFTER the last such sound.
  fun audio_buffer_new = minaudio_audio_buffer_new(
    data : Void*, size : SizeT, out_result : Int32*
  ) : Void*
  fun audio_buffer_new_from_file = minaudio_audio_buffer_new_from_file(
    path : UInt8*, out_result : Int32*
  ) : Void*
  fun audio_buffer_channels = minaudio_audio_buffer_channels(buf : Void*) : UInt32
  fun audio_buffer_rate = minaudio_audio_buffer_rate(buf : Void*) : UInt32
  fun audio_buffer_frames = minaudio_audio_buffer_frames(buf : Void*) : UInt64
  fun audio_buffer_free = minaudio_audio_buffer_free(buf : Void*) : Void

  # ---- ext ring-capture helpers (0.2.0) --------------------------------
  # Opaque per-device capture state over a FIXED ring of `ring_frames`
  # f32 frames: the data callback appends, the read side never blocks,
  # overflow drops the incoming frames (never grows unbounded). Init
  # leaves the device STOPPED — call ring_start explicitly. Free with
  # ring_free.
  fun ring_new = minaudio_ring_new(
    rate : Int32, channels : Int32, ring_frames : Int32,
    backends : Int32*, backend_count : Int32, out_result : Int32*
  ) : Void*
  fun ring_start = minaudio_ring_start(cap : Void*) : Int32
  fun ring_stop = minaudio_ring_stop(cap : Void*) : Int32
  fun ring_read = minaudio_ring_read(
    cap : Void*, out : Float32*, max_frames : UInt64
  ) : UInt64
  fun ring_available = minaudio_ring_available(cap : Void*) : UInt64
  fun ring_rate = minaudio_ring_rate(cap : Void*) : Int32
  fun ring_channels = minaudio_ring_channels(cap : Void*) : Int32
  fun ring_free = minaudio_ring_free(cap : Void*) : Void

  # ma_backend enum (priority order; see the header's "Backend enums
  # must be in priority order" block).
  BACKEND_WASAPI     =  0
  BACKEND_DSOUND     =  1
  BACKEND_WINMM      =  2
  BACKEND_COREAUDIO  =  3
  BACKEND_SNDIO      =  4
  BACKEND_AUDIO4     =  5
  BACKEND_OSS        =  6
  BACKEND_PULSEAUDIO =  7
  BACKEND_ALSA       =  8
  BACKEND_AAUDIO     =  9
  BACKEND_OPENSL     = 10

  # ---- ma_engine ------------------------------------------------------
  # config is NULL for defaults (no custom config binding yet).
  fun engine_init = ma_engine_init(config : Void*, engine : Void*) : Int32
  fun engine_uninit = ma_engine_uninit(engine : Void*) : Void
  fun engine_start = ma_engine_start(engine : Void*) : Int32
  fun engine_stop = ma_engine_stop(engine : Void*) : Int32
  fun engine_get_channels = ma_engine_get_channels(engine : Void*) : UInt32
  fun engine_get_sample_rate = ma_engine_get_sample_rate(engine : Void*) : UInt32
  fun engine_set_volume = ma_engine_set_volume(engine : Void*, volume : Float32) : Int32
  fun engine_get_volume = ma_engine_get_volume(engine : Void*) : Float32
  # Fire-and-forget convenience (fully decoded, managed by the engine).
  fun engine_play_sound = ma_engine_play_sound(
    engine : Void*, path : UInt8*, group : Void*
  ) : Int32

  # ---- ma_sound ---------------------------------------------------------
  # flags: MA_SOUND_FLAG_* constants below; 0 is the common default.
  fun sound_init_from_file = ma_sound_init_from_file(
    engine : Void*, path : UInt8*, flags : UInt32, group : Void*,
    done_fence : Void*, sound : Void*
  ) : Int32
  fun sound_init_copy = ma_sound_init_copy(
    engine : Void*, existing : Void*, flags : UInt32, group : Void*,
    sound : Void*
  ) : Int32
  # Sound over a decoded AudioBuffer (in-memory PCM, no file I/O). The
  # buffer must outlive the sound — the Crystal Sound keeps a reference.
  # ma_audio_buffer is a data source (ref.ds is its first member), so it
  # feeds ma_sound_init_from_data_source directly.
  fun sound_init_from_data_source = ma_sound_init_from_data_source(
    engine : Void*, data_source : Void*, flags : UInt32, group : Void*,
    sound : Void*
  ) : Int32
  fun sound_uninit = ma_sound_uninit(sound : Void*) : Void
  fun sound_start = ma_sound_start(sound : Void*) : Int32
  fun sound_stop = ma_sound_stop(sound : Void*) : Int32
  fun sound_stop_with_fade_ms = ma_sound_stop_with_fade_in_milliseconds(
    sound : Void*, fade_ms : UInt64
  ) : Int32
  fun sound_set_volume = ma_sound_set_volume(sound : Void*, volume : Float32) : Void
  fun sound_get_volume = ma_sound_get_volume(sound : Void*) : Float32
  fun sound_set_pan = ma_sound_set_pan(sound : Void*, pan : Float32) : Void
  fun sound_get_pan = ma_sound_get_pan(sound : Void*) : Float32
  fun sound_set_pitch = ma_sound_set_pitch(sound : Void*, pitch : Float32) : Void
  fun sound_get_pitch = ma_sound_get_pitch(sound : Void*) : Float32
  fun sound_set_looping = ma_sound_set_looping(sound : Void*, looping : Int32) : Void
  fun sound_is_looping = ma_sound_is_looping(sound : Void*) : Int32
  fun sound_is_playing = ma_sound_is_playing(sound : Void*) : Int32
  fun sound_at_end = ma_sound_at_end(sound : Void*) : Int32
  fun sound_seek_to_second = ma_sound_seek_to_second(
    sound : Void*, seconds : Float32
  ) : Int32
  fun sound_get_cursor_in_seconds = ma_sound_get_cursor_in_seconds(
    sound : Void*, cursor : Float32*
  ) : Int32
  fun sound_get_length_in_seconds = ma_sound_get_length_in_seconds(
    sound : Void*, length : Float32*
  ) : Int32
  fun sound_set_fade_in_ms = ma_sound_set_fade_in_milliseconds(
    sound : Void*, volume_beg : Float32, volume_end : Float32,
    fade_ms : UInt64
  ) : Void
  fun sound_set_position = ma_sound_set_position(
    sound : Void*, x : Float32, y : Float32, z : Float32
  ) : Void

  # ma_sound_init_from_file flags (subset; see the header's MA_SOUND_FLAG_
  # block for the exotic ones).
  SOUND_FLAG_STREAM    = 0x00000001
  SOUND_FLAG_DECODE    = 0x00000002
  SOUND_FLAG_ASYNC     = 0x00000004
  SOUND_FLAG_LOOPING   = 0x00000008
  SOUND_FLAG_NO_PITCH  = 0x00002000

  # ---- ma_sound_group ---------------------------------------------------
  # parent NULL = the engine's master group.
  fun group_init = ma_sound_group_init(
    engine : Void*, flags : UInt32, parent : Void*, group : Void*
  ) : Int32
  fun group_uninit = ma_sound_group_uninit(group : Void*) : Void
  fun group_start = ma_sound_group_start(group : Void*) : Int32
  fun group_stop = ma_sound_group_stop(group : Void*) : Int32
  fun group_set_volume = ma_sound_group_set_volume(group : Void*, volume : Float32) : Void
  fun group_get_volume = ma_sound_group_get_volume(group : Void*) : Float32

  # ---- ma_decoder ---------------------------------------------------------
  # Init goes through the f32 helpers above; these operate on an
  # initialized decoder.
  fun decoder_uninit = ma_decoder_uninit(dec : Void*) : Int32
  fun decoder_read_pcm_frames = ma_decoder_read_pcm_frames(
    dec : Void*, frames_out : Void*, frame_count : UInt64, frames_read : UInt64*
  ) : Int32
  fun decoder_seek_to_pcm_frame = ma_decoder_seek_to_pcm_frame(
    dec : Void*, frame_index : UInt64
  ) : Int32
  fun decoder_get_cursor_in_pcm_frames = ma_decoder_get_cursor_in_pcm_frames(
    dec : Void*, cursor : UInt64*
  ) : Int32
  fun decoder_get_length_in_pcm_frames = ma_decoder_get_length_in_pcm_frames(
    dec : Void*, length : UInt64*
  ) : Int32

  # ---- ma_context / device enumeration ------------------------------------
  # backends NULL + count 0 = let miniaudio pick. config NULL = defaults.
  fun context_init = ma_context_init(
    backends : Void*, backend_count : UInt32, config : Void*, ctx : Void*
  ) : Int32
  fun context_uninit = ma_context_uninit(ctx : Void*) : Int32
  fun context_get_devices = ma_context_get_devices(
    ctx : Void*, playback_infos : Void**, playback_count : UInt32*,
    capture_infos : Void**, capture_count : UInt32*
  ) : Int32
end
