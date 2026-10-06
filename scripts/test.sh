#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
test_binary="$(mktemp -t explorink-codec.XXXXXX)"
trap 'rm -f "$test_binary"' EXIT
cc -std=c11 -Wall -Wextra -Werror -pedantic -IExplorInkGPS \
    ExplorInkGPS/PositionCodec.c Tests/test_codec.c -lm -o "$test_binary"
"$test_binary"
python3 -m unittest discover -s Tests -p 'test_*.py'
