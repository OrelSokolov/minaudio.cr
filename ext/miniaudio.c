/* ext/miniaudio.c — the compiled miniaudio implementation + small helpers
 * that keep the Crystal side free of struct-by-value marshalling and
 * version-fragile layout knowledge:
 *
 *   - sizeof accessors for the caller-allocated types (ma_engine,
 *     ma_sound, ma_decoder, ma_context, ma_sound_group are init'd into
 *     caller memory; Crystal allocates opaque byte buffers of these
 *     sizes instead of mirroring every struct)
 *   - decoder init with an f32 conversion config (ma_decoder_config_init
 *     returns a config struct BY VALUE — awkward over FFI, so it is
 *     built here)
 *   - ma_device_info field accessors for enumeration (the struct embeds
 *     unions whose layout differs per backend)
 *
 * Build with `rake build` → lib/libminaudio.a; link flags live in
 * src/minaudio/lib.cr (@[Link] attributes), so an app only needs
 * -L<shard>/lib on its command line.
 */

#define MINIAUDIO_IMPLEMENTATION
#define MA_NO_ENCODING /* no file-writing APIs — playback/decode only */
#include "../vendor/miniaudio.h"

#include <stddef.h>
#include <string.h>

size_t minaudio_sizeof_engine(void)      { return sizeof(ma_engine); }
size_t minaudio_sizeof_sound(void)       { return sizeof(ma_sound); }
size_t minaudio_sizeof_decoder(void)     { return sizeof(ma_decoder); }
size_t minaudio_sizeof_context(void)     { return sizeof(ma_context); }
size_t minaudio_sizeof_sound_group(void) { return sizeof(ma_sound_group); }

/* ma_device_id is a 64-byte union blob as far as consumers are concerned. */
size_t minaudio_sizeof_device_id(void) { return sizeof(ma_device_id); }

/* ---- Decoder helpers (f32-converted output) -------------------------- */

/* channels/rate 0 = keep the source's. Config built here because
 * ma_decoder_config_init returns the struct by value. */
ma_result minaudio_decoder_init_memory_f32(const void* data, size_t size,
                                           ma_uint32 channels,
                                           ma_uint32 rate,
                                           ma_decoder* dec) {
    ma_decoder_config cfg =
        ma_decoder_config_init(ma_format_f32, channels, rate);
    return ma_decoder_init_memory(data, size, &cfg, dec);
}

ma_result minaudio_decoder_init_file_f32(const char* path, ma_uint32 channels,
                                         ma_uint32 rate, ma_decoder* dec) {
    ma_decoder_config cfg =
        ma_decoder_config_init(ma_format_f32, channels, rate);
    return ma_decoder_init_file(path, &cfg, dec);
}

/* ---- Backend-pinned engine init ---------------------------------------
 * ma_engine_init(NULL) lets miniaudio pick its highest-priority backend
 * (AAudio on Android). Some vendor builds refuse AAudio stream opens
 * for native-activity apps; pinning the backend list (OpenSL ES is the
 * universally reliable fallback) needs a context created here — the
 * engine keeps the pointer, so the context is heap-allocated and freed
 * by minaudio_context_free AFTER ma_engine_uninit.
 */
ma_result minaudio_context_create(const int* backends, int count,
                                  ma_context** out) {
    ma_backend bs[8];
    int n = (count > 8) ? 8 : count;
    for (int i = 0; i < n; i++) bs[i] = (ma_backend)backends[i];
    ma_context* c = (ma_context*)malloc(sizeof(ma_context));
    if (!c) return MA_OUT_OF_MEMORY;
    ma_result r = ma_context_init(n > 0 ? bs : NULL, (ma_uint32)n, NULL, c);
    if (r != MA_SUCCESS) { free(c); return r; }
    *out = c;
    return MA_SUCCESS;
}

void minaudio_context_free(ma_context* c) {
    if (c) { ma_context_uninit(c); free(c); }
}

ma_result minaudio_engine_init_ctx(ma_context* ctx, ma_engine* engine) {
    ma_engine_config cfg = ma_engine_config_init();
    cfg.pContext = ctx;
    return ma_engine_init(&cfg, engine);
}

/* ma_decoder_get_data_format needs five out-params; channels/rate are all
 * the Crystal API exposes (the format is f32 by construction). */
ma_result minaudio_decoder_format(ma_decoder* dec, ma_uint32* channels,
                                  ma_uint32* rate) {
    ma_format fmt;
    return ma_decoder_get_data_format(dec, &fmt, channels, rate, NULL, 0);
}

/* ---- Device enumeration helpers -------------------------------------- */

const char* minaudio_device_info_name(const ma_device_info* info) {
    return info->name;
}

/* Copy the opaque device id (safe across backend layouts). */
void minaudio_device_info_id_copy(const ma_device_info* info,
                                  unsigned char* out) {
    memcpy(out, &info->id, sizeof(ma_device_id));
}
