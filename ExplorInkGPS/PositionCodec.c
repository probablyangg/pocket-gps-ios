#include "PositionCodec.h"
#include <math.h>
#include <string.h>

static void little16(uint8_t *p, uint16_t n) {
    p[0] = (uint8_t)n; p[1] = (uint8_t)(n >> 8);
}
static void little32(uint8_t *p, uint32_t n) {
    for (unsigned i = 0; i < 4; ++i) p[i] = (uint8_t)(n >> (8 * i));
}
static double clamp(double n, double lo, double hi) { return fmin(hi, fmax(lo, n)); }
static uint8_t byteValue(double n) {
    return isfinite(n) ? (uint8_t)floor(clamp(n, 0, 255) + 0.5) : 0;
}

bool EIEncodePosition(EIFix f, uint8_t *out, size_t capacity) {
    if (!out || capacity < EI_PACKET_SIZE || !isfinite(f.latitude) ||
        !isfinite(f.longitude) || fabs(f.latitude) > 90 || fabs(f.longitude) > 180 ||
        !isfinite(f.horizontalAccuracy) || f.horizontalAccuracy < 0) return false;
    memset(out, 0, EI_PACKET_SIZE);
    // Match the protocol's nearest-integer rounding (half toward +infinity).
    little32(out, (uint32_t)(int32_t)floor(f.latitude * 1e7 + 0.5));
    little32(out + 4, (uint32_t)(int32_t)floor(f.longitude * 1e7 + 0.5));
    little32(out + 8, f.utcSeconds);
    little16(out + 12, (uint16_t)f.timezoneMinutes);
    out[15] = f.sequence;
    // Course describes movement, not where the phone happens to point.
    unsigned quality = 3; // Unknown: do not invent a north-facing arrow.
    if (isfinite(f.courseDegrees) && f.courseDegrees >= 0 && f.courseDegrees < 360 &&
        isfinite(f.speedMPS) && f.speedMPS >= 0.5 &&
        isfinite(f.courseAccuracyDegrees) && f.courseAccuracyDegrees >= 0) {
        if (f.courseAccuracyDegrees <= 22.5) quality = 1;
        else if (f.courseAccuracyDegrees <= 67.5) quality = 2;
        if (quality != 3) out[14] = (uint8_t)((int)floor(f.courseDegrees / 22.5 + 0.5) % 16);
    }
    out[16] = (uint8_t)(quality << 2);
    out[17] = byteValue(f.horizontalAccuracy);
    if (out[17] == 0) out[17] = 1; // Zero means unknown on the reader.
    out[18] = byteValue(f.speedMPS * 3.6);
    if (f.altitudeValid && isfinite(f.altitudeMetres)) {
        out[16] |= 2;
        const int16_t altitude = (int16_t)floor(clamp(f.altitudeMetres, -32768, 32767) + 0.5);
        little16(out + 19, (uint16_t)altitude);
    }
    return true;
}
