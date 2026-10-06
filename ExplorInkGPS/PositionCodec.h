#ifndef POSITION_CODEC_H
#define POSITION_CODEC_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define EI_PACKET_SIZE 21
#define EI_SERVICE_UUID "5a1e6d00-73a4-4f1e-9b8f-2c6e1a8f0001"
#define EI_POSITION_UUID "5a1e6d00-73a4-4f1e-9b8f-2c6e1a8f0002"

typedef struct {
    double latitude, longitude;
    uint32_t utcSeconds;
    int16_t timezoneMinutes;
    double courseDegrees, courseAccuracyDegrees, speedMPS;
    double horizontalAccuracy, altitudeMetres;
    bool altitudeValid;
    uint8_t sequence;
} EIFix;

// Returns false for unusable coordinates/accuracy. Writes exactly 21 bytes.
bool EIEncodePosition(EIFix fix, uint8_t *output, size_t capacity);
#endif
