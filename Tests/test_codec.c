#include "PositionCodec.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

static uint32_t u32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static int16_t i16(const uint8_t *p) { return (int16_t)((unsigned)p[0] | ((unsigned)p[1] << 8)); }

int main(void) {
    uint8_t b[22]; memset(b, 0xa5, sizeof b);
    EIFix f = {.latitude=48.1485965, .longitude=17.1077477,
        .utcSeconds=1754240000, .timezoneMinutes=120, .courseDegrees=112.5,
        .courseAccuracyDegrees=10, .speedMPS=63.6/3.6,
        .horizontalAccuracy=7.4, .sequence=200};
    assert(EIEncodePosition(f, b, sizeof b));
    // Independent fixed bytes from the published protocol field values.
    const uint8_t expected[] = {0x8d,0xe4,0xb2,0x1c,0x65,0x6f,0x32,0x0a,
        0x00,0x94,0x8f,0x68,0x78,0x00,0x05,0xc8,0x04,0x07,0x40,0x00,0x00};
    // Also check field decoding to make a vector mismatch straightforward to diagnose.
    assert((int32_t)u32(b) == 481485965);
    assert((int32_t)u32(b+4) == 171077477);
    assert(u32(b+8) == 1754240000); assert(i16(b+12) == 120);
    assert(b[14] == 5 && b[15] == 200 && b[16] == 4 && b[17] == 7 && b[18] == 64);
    assert(memcmp(b, expected, 21) == 0);
    assert(b[21] == 0xa5); // No write beyond the wire packet.
    assert(!EIEncodePosition(f, b, 20));
    assert(!EIEncodePosition(f, NULL, 21));

    f.latitude=-33.8688; f.longitude=-151.2093; f.timezoneMinutes=-300;
    f.utcSeconds=2200000000U; f.altitudeValid=true; f.altitudeMetres=-420;
    assert(EIEncodePosition(f,b,21));
    assert((int32_t)u32(b)==-338688000 && (int32_t)u32(b+4)==-1512093000);
    assert(i16(b+12)==-300 && i16(b+19)==-420 && b[16]==6);
    assert(u32(b+8)==2200000000U);
    f.altitudeMetres=0; EIEncodePosition(f,b,21); assert((b[16]&2) && i16(b+19)==0);
    f.altitudeMetres=1e99; EIEncodePosition(f,b,21); assert(i16(b+19)==32767);
    f.altitudeMetres=-1e99; EIEncodePosition(f,b,21); assert(i16(b+19)==-32768);
    f.altitudeMetres=NAN; EIEncodePosition(f,b,21); assert(!(b[16]&2));
    f.horizontalAccuracy=9999; f.speedMPS=1000;
    EIEncodePosition(f,b,21); assert(b[17]==255 && b[18]==255);
    f.courseDegrees=359; EIEncodePosition(f,b,21); assert(b[14]==0);
    f.courseDegrees=270; EIEncodePosition(f,b,21); assert(b[14]==12);
    f.courseAccuracyDegrees=40; EIEncodePosition(f,b,21); assert((b[16]&12)==8);
    f.courseAccuracyDegrees=-1; EIEncodePosition(f,b,21); assert((b[16]&12)==12 && b[14]==0);
    f.courseAccuracyDegrees=10; f.speedMPS=0; EIEncodePosition(f,b,21); assert((b[16]&12)==12);
    f.speedMPS=-1; EIEncodePosition(f,b,21); assert(b[18]==0);
    f.latitude=NAN; assert(!EIEncodePosition(f,b,21));
    f.latitude=91; assert(!EIEncodePosition(f,b,21));
    f.latitude=0; f.longitude=181; assert(!EIEncodePosition(f,b,21));
    f.longitude=0; f.horizontalAccuracy=-1; assert(!EIEncodePosition(f,b,21));
    f.horizontalAccuracy=0.1; EIEncodePosition(f,b,21); assert(b[17]==1);
    f.latitude=-90; f.longitude=180; assert(EIEncodePosition(f,b,21));
    assert((int32_t)u32(b)==-900000000 && u32(b+4)==1800000000);
    puts("PASS: packet layout, signed fields, bounds, quality flags, altitude, and invalid inputs");
}
