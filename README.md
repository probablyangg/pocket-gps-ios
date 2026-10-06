# Pocket GPS for ExplorInk — iPhone prototype

A native iPhone companion that sends your location to an ExplorInk reader over Bluetooth LE. Created for the Xteink X4 Pro; it discovers the standard ExplorInk position service, so other readers exposing that same protocol may work.

**Status: source prototype, not a signed or hardware-tested app.** The packet encoder and map utility have been tested here. Swift syntax and Xcode project structure have been checked. This environment has no Xcode or Apple SDK, so the iOS target has not been compiled, installed, or exercised on an iPhone/X4 Pro. The first Xcode build may reveal SDK or signing issues that these checks cannot detect.

## What is included

- An Xcode project with SwiftUI screens, CoreBluetooth connection handling, and CoreLocation.
- Explicit reader selection and Start/Stop sharing controls. Finding or connecting to a reader alone does not start GPS.
- Acknowledged, exactly 21-byte position writes using the reader's published UUIDs.
- Position, time/timezone, course quality, accuracy, speed, altitude and sequence fields.
- New fixes only: reject fixes older than 10 seconds, invalid coordinates, or horizontal accuracy worse than 100 m.
- A maximum write rate of once per three seconds; stationary updates reduce to at most once per 15 seconds while fresh fixes arrive.
- Foreground-started background location and Bluetooth modes, intended for a locked phone. Actual locked-screen reliability needs device testing.
- Reconnect to the selected reader during a running session, with a two-minute deadline. GPS stops when that deadline expires.
- No account, analytics, location log, network requests from the app, or saved location history. The UI holds the current fix in memory.
- A separate Python map preloader for a Mac/computer, to prepare an SD card without an Android phone.

This is **not** the full Android app port: automatic Bluetooth map downloads, route recording, pins, turn-by-turn directions, and launch-on-reader-detection are not implemented. Relaunching or force-quitting the iPhone app does not resume sharing automatically. It uses the existing unpaired ExplorInk BLE protocol; it does not add authentication or encryption guarantees.

## Install on your iPhone

1. Extract this folder on a Mac with Xcode. The deployment target is iOS 17 or newer; use an Xcode version that supports your installed iOS version.
2. Open `ExplorInkGPS.xcodeproj`. No CocoaPods, Swift packages, XcodeGen, or other dependencies are needed.
3. Select the `ExplorInkGPS` target → **Signing & Capabilities**. Select your development team and replace `com.example.explorink.pocketgps` with a unique bundle identifier.
4. Connect your iPhone, select it as the run destination, and enable Developer Mode if iOS/Xcode asks. Press Run. Device signing uses your own Apple account; no signing credentials are included.
5. Your X4 Pro must already be running ExplorInk's **X4 Pro-specific firmware**, with map tiles on its FAT32 SD card. Stock Xteink firmware and ordinary CrossPoint reader firmware do not provide this map service. Use the [upstream installation instructions](https://explorink.com/install/), including their stock-flash backup procedure, when the device arrives. This project does not flash the reader.
6. Open **Explore** on the reader. In Pocket GPS, tap **Find my reader**, allow Bluetooth, select the reader, then tap **Start sharing location**.
7. Grant **While Using the App** location permission with Precise Location enabled. Begin the session while Pocket GPS is visible, then lock the phone. Background location can show iOS's location indicator.

Stop sharing turns GPS off. Disconnect also releases Bluetooth. A transport acknowledgement in the app confirms the Bluetooth write; it does not prove that ExplorInk has parsed the packet or redrawn the screen.

## Preload maps without Android

The reader cannot draw streets until it has tiles. The included tool downloads available format-v4 base tiles at zoom levels 11, 12, and 13 into a staging folder. It checks tile identity, header CRC, layer CRCs, and basic bounds before saving. It never flashes or directly accesses your device.

From this extracted folder on your Mac, with Python 3 installed:

```sh
python3 scripts/preload_maps.py --lat 43.6532 --lon -79.3832 --width-km 10 --dry-run
python3 scripts/preload_maps.py --lat 43.6532 --lon -79.3832 --width-km 10 --output maps-to-copy
```

These example coordinates are central Toronto, not your live location. Change them to the area you want. The width describes an approximate square centred there, not a radius. The tool sends tile requests for that area to ExplorInk's public server. It accepts widths up to 20 km and rejects plans over 500 files.

Copy `maps-to-copy/trailink` to the **root** of the reader's FAT32 SD card using a card reader. Preserve the structure, e.g. `/trailink/base/13/<x>/<y>.tib`. Merge with an existing folder; do not replace/delete unrelated card contents. Eject the card before putting it back in the reader.

Coverage is incomplete. Missing tiles are reported and produce exit code 2, rather than claiming a complete offline area. Their server may build requested areas later, but this tool does not guarantee that; see the [coverage map](https://tiles.explorink.com). Rerunning skips existing valid files. It does not refresh them, download points-of-interest files, or build tiles locally. The script specifically targets v4; verify your firmware uses v4 before copying. The live check performed here used a public Bratislava tile, not Toronto coverage.

## First device check

1. While outdoors, confirm an accurate location appears and the acknowledged write count increases.
2. Confirm the reader's marker matches the iPhone location, then walk far enough to move the marker.
3. Lock the phone for five minutes and confirm the marker keeps following. Record the iOS version and firmware release if it does not.
4. Briefly move out of Bluetooth range and return within two minutes. Confirm reconnection and a new fix. Stay out of range for longer than two minutes and confirm sharing stops.
5. Tap Stop and verify the iOS location indicator ends. The reader may retain its last marker; it is no longer live.
6. Deny Bluetooth/location permission, turn Bluetooth off, and try a session without GPS reception. Verify that the UI reports the actual condition rather than claiming live sharing.

The iOS simulator can be used for a build/UI check, but not to prove the physical BLE path.

## Validation

Run portable tests on macOS/Linux:

```sh
sh scripts/test.sh
```

Run the Apple SDK build on a Mac:

```sh
xcodebuild -project ExplorInkGPS.xcodeproj -scheme ExplorInkGPS \
  -sdk iphonesimulator -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

Checks completed in the creation environment:

- Compiled C encoder tests: fixed byte vector, negative coordinates/timezone, unsigned timestamps, altitude flags/saturation, heading quality, small output buffers, and invalid inputs.
- Five Python tests: tile coordinate planning, all zoom levels, antimeridian wrapping, invalid inputs, and corrupt/truncated tile rejection.
- One live v4 tile (Bratislava, `13/4485/2842`, 669,401 bytes): identity, header CRC and every layer CRC validated.
- Swift source parsed without syntax errors; plist XML and all Xcode object/source references validated. These are not a substitute for an Apple SDK build.

## Protocol provenance

Inspected on 2026-10-06:

- [ExplorInk firmware](https://github.com/rfordinal/explorink), commit `22dff53a7abe512011ffd9608ea4e7516e5d770d`: `lib/BlePositionServer/include/BlePositionServer.h`, `lib/BlePositionServer/src/BlePositionServer.cpp`, and `src/activities/map/MapTileReader.cpp`.
- [Android sender](https://github.com/rfordinal/explorink-android), commit `a32e6df9c25dc45346cc00d4a71323a8ea321b5d`: `PositionPacket.kt`, `BleLink.kt`, `TileSource.kt` and `TileBox.kt` were read to cross-check interoperability. Android source is not bundled.
- [Apple background location](https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates) and [CoreBluetooth](https://developer.apple.com/documentation/corebluetooth/).

Service: `5a1e6d00-73a4-4f1e-9b8f-2c6e1a8f0001`.
Position characteristic: `5a1e6d00-73a4-4f1e-9b8f-2c6e1a8f0002`.
Transport: one 21-byte **write with response**, never fragmented into multiple characteristic writes.

| Byte offset | Field | Encoding |
|---|---|---|
| 0–3 | Latitude | signed int32, degrees × 10⁷ |
| 4–7 | Longitude | signed int32, degrees × 10⁷ |
| 8–11 | Current UTC | unsigned int32, Unix seconds |
| 12–13 | Timezone | signed int16, minutes east of UTC |
| 14 | Heading | 0–15 clockwise sectors; north is 0 |
| 15 | Sequence | wrapping uint8 |
| 16 | Flags | bit 1 altitude present; bits 2–3 heading quality |
| 17 | Accuracy | metres, saturated uint8; 0 is unknown |
| 18 | Speed | km/h, saturated uint8 |
| 19–20 | Altitude | signed int16 metres |

All multi-byte fields are little-endian. Heading uses course of travel; a stationary or unreliable course is marked unknown. This protocol is evolving and has no version negotiation in this minimal position-only app.

This is an independent companion prototype, unaffiliated with ExplorInk, Xteink, or CrossPoint. Map data is © OpenStreetMap contributors, distributed under ODbL by the upstream tile service.
