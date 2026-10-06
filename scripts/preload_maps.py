#!/usr/bin/env python3
"""Download a small ExplorInk area into an SD-card-ready staging directory.
Uses only the Python standard library. Does not flash or write to a reader.
"""
import argparse
import math
from pathlib import Path
import struct
import urllib.error
import urllib.request
import zlib

MAX_LAT = 85.0511287798066
MAX_BYTES = 8 * 1024 * 1024

def tile(latitude, longitude, zoom):
    n = 1 << zoom
    lat = math.radians(max(-MAX_LAT, min(MAX_LAT, latitude)))
    x = int(math.floor((longitude + 180) / 360 * n)) % n
    y = int(math.floor((1 - math.asinh(math.tan(lat)) / math.pi) / 2 * n))
    return x, max(0, min(n - 1, y))

def area_tiles(latitude, longitude, side_km):
    if not all(math.isfinite(v) for v in (latitude, longitude, side_km)):
        raise ValueError("Coordinates and area width must be finite")
    if not (-80 <= latitude <= 80 and -180 <= longitude <= 180 and 0 < side_km <= 20):
        raise ValueError("Use latitude -80..80, longitude -180..180, and width 0..20 km")
    half_lat = side_km * 500 / 111320
    half_lon = half_lat / math.cos(math.radians(latitude))
    result = []
    for z in (11, 12, 13):
        left, bottom = tile(latitude - half_lat, longitude - half_lon, z)
        right, top = tile(latitude + half_lat, longitude + half_lon, z)
        n = 1 << z
        columns = (right - left) % n + 1
        for dx in range(columns):
            for y in range(top, bottom + 1):
                result.append((z, (left + dx) % n, y))
    if len(result) > 500:
        raise ValueError("Area needs over 500 tiles; choose a smaller width")
    return result

def validate(data, version, z, x, y):
    if version != 4:
        raise ValueError("This preloader supports only format v4")
    if not 37 <= len(data) <= MAX_BYTES or data[:4] != b'TIB1':
        raise ValueError("Not a complete TIB tile header")
    got_version, got_z, got_x, got_y = struct.unpack_from('<HBII', data, 4)
    if (got_version, got_z, got_x, got_y) != (version, z, x, y):
        raise ValueError("Tile format or coordinates do not match the request")
    # v4 added coord_shift at byte 31: CRC is at 32, layer_count at 36.
    # Older Android header comments still describe v3's 36-byte header.
    layer_count = data[36]
    directory_end = 37 + layer_count * 21
    if directory_end > len(data):
        raise ValueError("Truncated layer directory")
    header = bytearray(data[:directory_end])
    expected_crc = struct.unpack_from('<I', header, 32)[0]
    header[32:36] = b'\0' * 4
    if zlib.crc32(header) != expected_crc:
        raise ValueError("Tile header checksum mismatch")
    for i in range(layer_count):
        at = 37 + i * 21
        offset, length, crc, index_offset, index_length = struct.unpack_from('<IIIII', data, at + 1)
        if offset + length > len(data) or (length and offset < directory_end):
            raise ValueError("Truncated layer payload")
        if zlib.crc32(data[offset:offset+length]) != crc:
            raise ValueError("Layer checksum mismatch")
        if index_offset + index_length > len(data):
            raise ValueError("Truncated layer index")

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lat', type=float, required=True)
    parser.add_argument('--lon', type=float, required=True)
    parser.add_argument('--width-km', type=float, default=10)
    parser.add_argument('--output', type=Path, default=Path('maps-to-copy'))
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    try:
        tiles = area_tiles(args.lat, args.lon, args.width_km)
    except ValueError as error:
        parser.error(str(error))
    print(f'{len(tiles)} tile files, format v4, zoom levels 11–13.')
    if args.dry_run:
        return 0
    complete = missing = failed = 0
    for z, x, y in tiles:
        relative = Path('trailink') / 'base' / str(z) / str(x) / f'{y}.tib'
        target = args.output / relative
        try:
            if target.exists():
                validate(target.read_bytes(), 4, z, x, y)
                complete += 1
                continue
            url = f'https://tiles.explorink.com/v4/base/{z}/{x}/{y}.tib'
            request = urllib.request.Request(url, headers={'User-Agent': 'PocketGPS-preload/0.1'})
            with urllib.request.urlopen(request, timeout=20) as response:
                data = response.read(MAX_BYTES + 1)
            validate(data, 4, z, x, y)
            target.parent.mkdir(parents=True, exist_ok=True)
            partial = target.with_suffix('.part')
            partial.write_bytes(data)
            partial.replace(target)
            complete += 1
        except urllib.error.HTTPError as error:
            if error.code == 404:
                missing += 1
                print(f'Unavailable: {z}/{x}/{y}')
            else:
                failed += 1
                print(f'HTTP {error.code}: {z}/{x}/{y}')
        except (OSError, ValueError) as error:
            failed += 1
            print(f'Failed {z}/{x}/{y}: {error}')
    print(f'{complete} ready, {missing} not yet available, {failed} failed.')
    print(f'Copy {args.output / "trailink"} to the root of a FAT32 SD card, preserving folders.')
    print('Missing coverage remains missing; this script does not guarantee a server rebuild.')
    return 0 if missing == failed == 0 else 2

if __name__ == '__main__':
    raise SystemExit(main())
