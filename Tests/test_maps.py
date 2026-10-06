import importlib.util
from pathlib import Path
import struct
import unittest
import zlib

spec = importlib.util.spec_from_file_location('preload', Path(__file__).parents[1] / 'scripts/preload_maps.py')
preload = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preload)

class MapsTests(unittest.TestCase):
    def test_equator_and_zoom_coverage(self):
        self.assertEqual(preload.tile(0, 0, 11), (1024, 1024))
        tiles = preload.area_tiles(43.65, -79.38, 10)
        self.assertEqual({z for z, x, y in tiles}, {11, 12, 13})
        for z in (11, 12, 13):
            x, y = preload.tile(43.65, -79.38, z)
            self.assertIn((z, x, y), tiles)

    def test_antimeridian_is_small_and_unique(self):
        tiles = preload.area_tiles(0, 179.999, 10)
        self.assertLess(len(tiles), 100)
        self.assertEqual(len(tiles), len(set(tiles)))
        self.assertIn(0, [x for z, x, y in tiles])

    def test_invalid_area(self):
        for coordinates in ((float('nan'), 0, 10), (90, 0, 10), (0, 181, 10), (0, 0, 500)):
            with self.assertRaises(ValueError): preload.area_tiles(*coordinates)

    def test_wrong_or_truncated_tile(self):
        data = bytearray(37)
        data[:4] = b'TIB1'
        struct.pack_into('<HBII', data, 4, 4, 13, 100, 200)
        struct.pack_into('<I', data, 32, zlib.crc32(data))
        preload.validate(data, 4, 13, 100, 200)
        with self.assertRaises(ValueError): preload.validate(data, 4, 13, 101, 200)
        with self.assertRaises(ValueError): preload.validate(data, 3, 13, 100, 200)
        data[36] = 1
        with self.assertRaises(ValueError): preload.validate(data, 4, 13, 100, 200)

    def test_checksum_rejects_corruption(self):
        data = bytearray(37)
        data[:4] = b'TIB1'
        struct.pack_into('<HBII', data, 4, 4, 13, 100, 200)
        struct.pack_into('<I', data, 32, zlib.crc32(data))
        data[20] ^= 1
        with self.assertRaisesRegex(ValueError, 'checksum'):
            preload.validate(data, 4, 13, 100, 200)
