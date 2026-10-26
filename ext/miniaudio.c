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

/* ---- Capture helpers (VoiceRecorder) -----------------------------------
 * ma_device in read mode blocks until samples arrive, which the UI frame
 * loop must never do — so the device runs with a data callback that
 * appends s16 samples to a mutex-guarded heap buffer, and the frame
 * thread only ever calls the non-blocking drain below (the audio analog
 * of the camera's latest-frame slot). The whole per-device state is one
 * heap object handed back to Crystal as an opaque pointer.
 */
typedef struct {
    ma_device dev;
    ma_context* ctx;   /* backend-pinned context (NULL = device-internal) */
    ma_mutex lock;     /* guards buf/len/cap */
    unsigned char* buf;
    size_t len, cap;
    ma_uint32 sample_rate, channels;
} minaudio_capture;

static void minaudio_capture_cb(ma_device* pDevice, void* pOutput,
                                const void* pInput, ma_uint32 frameCount) {
    (void)pOutput;
    minaudio_capture* c = (minaudio_capture*)pDevice->pUserData;
    if (!c || !pInput || frameCount == 0) return;
    size_t n = (size_t)frameCount * c->channels * sizeof(ma_int16);
    ma_mutex_lock(&c->lock);
    if (c->len + n > c->cap) {
        size_t ncap = c->cap ? c->cap : 16384;
        while (ncap < c->len + n) ncap *= 2;
        unsigned char* nb = (unsigned char*)realloc(c->buf, ncap);
        if (nb) { c->buf = nb; c->cap = ncap; } else { n = 0; /* OOM: drop */ }
    }
    if (n) { memcpy(c->buf + c->len, pInput, n); c->len += n; }
    ma_mutex_unlock(&c->lock);
}

/* device_id NULL = the default capture device. backends NULL/count 0 =
 * miniaudio's default priority order. *out_result gets the ma_result
 * (the void* return only says success). Init leaves the device STOPPED
 * — call minaudio_capture_start explicitly.
 */
void* minaudio_capture_new(const unsigned char* device_id, int rate,
                           int channels, const int* backends, int count,
                           int* out_result) {
    minaudio_capture* c =
        (minaudio_capture*)calloc(1, sizeof(minaudio_capture));
    if (!c) { *out_result = MA_OUT_OF_MEMORY; return NULL; }
    ma_mutex_init(&c->lock);

    ma_device_config cfg = ma_device_config_init(ma_device_type_capture);
    cfg.sampleRate = (ma_uint32)rate;
    cfg.capture.format = ma_format_s16;
    cfg.capture.channels = (ma_uint32)channels;
    cfg.capture.shareMode = ma_share_mode_shared;
    cfg.dataCallback = minaudio_capture_cb;
    cfg.pUserData = c;

    /* pDeviceID must point at memory living through ma_device_init only —
     * copy the caller's blob onto the heap for that window. */
    ma_device_id* id_copy = NULL;
    if (device_id) {
        id_copy = (ma_device_id*)malloc(sizeof(ma_device_id));
        if (id_copy) {
            memcpy(id_copy, device_id, sizeof(ma_device_id));
            cfg.capture.pDeviceID = id_copy;
        }
    }

    ma_result r;
    if (backends && count > 0) {
        r = minaudio_context_create(backends, count, &c->ctx);
        if (r == MA_SUCCESS)
            r = ma_device_init(c->ctx, &cfg, &c->dev);
    } else {
        r = ma_device_init(NULL, &cfg, &c->dev);
    }
    free(id_copy);
    if (r != MA_SUCCESS) {
        if (c->ctx) minaudio_context_free(c->ctx);
        ma_mutex_uninit(&c->lock);
        free(c);
        *out_result = r;
        return NULL;
    }
    /* The data converter guarantees the configured format/channels/rate
     * in the callback; report what the device actually settled on. */
    c->sample_rate = c->dev.sampleRate > 0 ? c->dev.sampleRate
                                           : (ma_uint32)rate;
    c->channels = c->dev.capture.channels > 0 ? c->dev.capture.channels
                                              : (ma_uint32)channels;
    *out_result = MA_SUCCESS;
    return c;
}

int minaudio_capture_start(void* p) {
    minaudio_capture* c = (minaudio_capture*)p;
    return c ? ma_device_start(&c->dev) : MA_INVALID_ARGS;
}

int minaudio_capture_stop(void* p) {
    minaudio_capture* c = (minaudio_capture*)p;
    return c ? ma_device_stop(&c->dev) : MA_INVALID_ARGS;
}

/* Copy out (and drop) up to cap_len accumulated bytes; returns how many
 * were written — 0 means nothing new since the last drain. Never blocks. */
size_t minaudio_capture_drain(void* p, unsigned char* out, size_t cap_len) {
    minaudio_capture* c = (minaudio_capture*)p;
    if (!c || !out) return 0;
    ma_mutex_lock(&c->lock);
    size_t n = c->len < cap_len ? c->len : cap_len;
    if (n > 0) {
        memcpy(out, c->buf, n);
        memmove(c->buf, c->buf + n, c->len - n);
        c->len -= n;
    }
    ma_mutex_unlock(&c->lock);
    return n;
}

/* Bytes waiting right now (level meters / tests; never blocks). */
size_t minaudio_capture_pending(void* p) {
    minaudio_capture* c = (minaudio_capture*)p;
    if (!c) return 0;
    ma_mutex_lock(&c->lock);
    size_t n = c->len;
    ma_mutex_unlock(&c->lock);
    return n;
}

int minaudio_capture_rate(void* p) {
    minaudio_capture* c = (minaudio_capture*)p;
    return c ? (int)c->sample_rate : 0;
}

int minaudio_capture_channels(void* p) {
    minaudio_capture* c = (minaudio_capture*)p;
    return c ? (int)c->channels : 0;
}

void minaudio_capture_free(void* p) {
    minaudio_capture* c = (minaudio_capture*)p;
    if (!c) return;
    ma_device_uninit(&c->dev); /* stops the device if still running */
    if (c->ctx) minaudio_context_free(c->ctx); /* AFTER device uninit */
    ma_mutex_uninit(&c->lock);
    free(c->buf);
    free(c);
}
