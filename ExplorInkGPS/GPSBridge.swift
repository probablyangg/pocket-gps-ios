import Foundation
import Combine
import CoreBluetooth
import CoreLocation
import UIKit

struct Reader: Identifiable {
    let id: UUID
    let name: String
    var signal: Int
}

// Both delegate queues are main. Swift 5 language mode avoids implicit actor
// isolation; no background queue touches UI, CoreLocation, or the BLE session.
final class GPSBridge: NSObject, ObservableObject {
    @Published private(set) var readers: [Reader] = []
    @Published private(set) var status = "Ready to find your reader"
    @Published private(set) var detail = "Open Explore on your X4 Pro first."
    @Published private(set) var scanning = false
    @Published private(set) var connecting = false
    @Published private(set) var connected = false
    @Published private(set) var sharing = false
    @Published private(set) var readerName = "No reader selected"
    @Published private(set) var lastFix: CLLocation?
    @Published private(set) var lastAcknowledged: Date?
    @Published private(set) var acknowledgedCount = 0
    @Published private(set) var needsSettings = false
    @Published private(set) var recentEvents: [String] = []

    private let serviceID = CBUUID(string: EI_SERVICE_UUID)
    private let positionID = CBUUID(string: EI_POSITION_UUID)
    private let location = CLLocationManager()
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var selected: CBPeripheral?
    private var position: CBCharacteristic?
    private var wantsScan = false
    private var updatingLocation = false
    private var pendingFix: CLLocation?
    private var sentFix: CLLocation?
    private var sentAt: Date?
    private var inFlight = false
    private var writeStarted: Date?
    private var writeFailures = 0
    private var sequence: UInt8 = 0
    private var timeout: DispatchWorkItem?
    private var reconnectUntil: Date?
    private var ticker: Timer?

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBest
        location.distanceFilter = kCLDistanceFilterNone
        location.activityType = .otherNavigation
        location.pausesLocationUpdatesAutomatically = false
        location.showsBackgroundLocationIndicator = true
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func findReaders() {
        guard !sharing && !connecting else { return }
        disconnect()
        readers = []; peripherals = [:]; needsSettings = false
        wantsScan = true
        status = "Preparing Bluetooth"
        detail = "Keep Explore open on the reader."
        if central == nil {
            // No restoration identifier: launch always requires an explicit
            // start; this prototype never silently resumes location sharing.
            central = CBCentralManager(delegate: self, queue: .main)
        } else {
            scanIfReady()
        }
    }

    func cancelScan() {
        wantsScan = false; scanning = false
        central?.stopScan(); timeout?.cancel()
        status = "Search stopped"
    }

    private func scanIfReady() {
        guard wantsScan, let central, central.state == .poweredOn else { return }
        scanning = true
        status = "Looking for ExplorInk readers"
        central.scanForPeripherals(withServices: [serviceID], options: nil)
        armTimeout(seconds: 20) { [weak self] in
            guard let self else { return }
            self.central?.stopScan(); self.wantsScan = false; self.scanning = false
            self.status = self.readers.isEmpty ? "No reader found" : "Choose your reader"
            self.detail = self.readers.isEmpty
                ? "Open Explore in ExplorInk firmware, bring the reader closer, and search again. Stock Xteink firmware does not provide this service."
                : "Connect to the reader you want to use."
        }
    }

    func connect(to reader: Reader) {
        guard !sharing, !connecting, let peripheral = peripherals[reader.id],
              let central, central.state == .poweredOn else { return }
        central.stopScan(); timeout?.cancel(); wantsScan = false; scanning = false
        selected = peripheral; peripheral.delegate = self
        readerName = reader.name; connecting = true
        status = "Connecting to \(reader.name)"; detail = "Checking the position service."
        central.connect(peripheral, options: nil)
        armTimeout(seconds: 20) { [weak self] in self?.failConnection("Connection timed out. Search again with Explore open.") }
    }

    func startSharing() {
        guard connected, !sharing else { return }
        sharing = true; needsSettings = false; acknowledgedCount = 0
        lastAcknowledged = nil; lastFix = nil; pendingFix = nil; sentFix = nil; sentAt = nil
        switch location.authorizationStatus {
        case .notDetermined:
            status = "Allow location access"
            detail = "Choose While Using the App. Start the session before locking your phone."
            location.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: beginLocation()
        default: locationDenied()
        }
    }

    private func beginLocation() {
        guard sharing, !updatingLocation else { return }
        guard UIApplication.shared.applicationState == .active else {
            sharing = false; status = "Open the app to start sharing"
            detail = "Start a new session while this app is visible."
            return
        }
        location.allowsBackgroundLocationUpdates = true
        updatingLocation = true
        location.startUpdatingLocation()
        status = "Waiting for a fresh location"
        detail = "Location goes directly to your selected reader over Bluetooth."
        event("Location session started")
    }

    func stopSharing() {
        sharing = false; reconnectUntil = nil
        location.stopUpdatingLocation(); location.allowsBackgroundLocationUpdates = false
        updatingLocation = false; pendingFix = nil; sentFix = nil; sentAt = nil
        if !connected { timeout?.cancel(); disconnectLink() }
        status = connected ? "Connected · sharing stopped" : "Sharing stopped"
        detail = "GPS updates are off. The reader may still show its last position."
        event("Location session stopped")
    }

    func disconnect() {
        stopSharing(); timeout?.cancel(); central?.stopScan()
        wantsScan = false; scanning = false
        disconnectLink()
        readerName = "No reader selected"
        status = "Disconnected"; detail = "Open Explore on your reader, then search."
    }

    private func disconnectLink() {
        let old = selected
        selected = nil; position = nil; connected = false; connecting = false
        inFlight = false; writeStarted = nil
        if let old { central?.cancelPeripheralConnection(old) }
    }

    private func locationDenied() {
        stopSharing(); needsSettings = true
        status = "Location access is unavailable"
        detail = "Enable Location Services and allow location access for this app in Settings."
    }

    private func failConnection(_ message: String) {
        stopSharing(); timeout?.cancel(); disconnectLink()
        status = "Connection unavailable"; detail = message; event(message)
    }

    private func armTimeout(seconds: TimeInterval, action: @escaping () -> Void) {
        timeout?.cancel()
        let work = DispatchWorkItem(block: action)
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func event(_ text: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        recentEvents.insert("\(time)  \(text)", at: 0)
        recentEvents = Array(recentEvents.prefix(12))
    }

    private func tick() {
        if let deadline = reconnectUntil, Date() >= deadline {
            failConnection("The reader stayed disconnected for two minutes. Location sharing has stopped.")
            return
        }
        if inFlight, let started = writeStarted, Date().timeIntervalSince(started) > 15 {
            failConnection("The reader stopped acknowledging location writes. Reconnect to try again.")
            return
        }
        if sharing, connected, let fix = lastFix, Date().timeIntervalSince(fix.timestamp) > 15 {
            status = "Waiting for a fresh location"
            detail = "The last fix is stale; it is not being resent. The reader may still display it."
        }
        sendIfReady()
    }

    private func sendIfReady() {
        guard sharing, connected, !inFlight, let peripheral = selected,
              let characteristic = position, let fix = pendingFix else { return }
        let now = Date()
        guard now.timeIntervalSince(fix.timestamp) >= -2,
              now.timeIntervalSince(fix.timestamp) <= 10 else { pendingFix = nil; return }
        if let sentAt {
            let elapsed = now.timeIntervalSince(sentAt)
            guard elapsed >= 3 else { return }
            // Avoid repainting an e-ink map for each stationary GPS wobble.
            if let previous = sentFix,
               fix.distance(from: previous) < max(5, min(20, fix.horizontalAccuracy)),
               elapsed < 15 { return }
        }
        var wire = EIFix()
        wire.latitude = fix.coordinate.latitude; wire.longitude = fix.coordinate.longitude
        wire.utcSeconds = UInt32(clamping: Int64(now.timeIntervalSince1970))
        wire.timezoneMinutes = Int16(clamping: TimeZone.current.secondsFromGMT(for: now) / 60)
        wire.courseDegrees = fix.course; wire.courseAccuracyDegrees = fix.courseAccuracy
        wire.speedMPS = fix.speed; wire.horizontalAccuracy = fix.horizontalAccuracy
        wire.altitudeMetres = fix.altitude; wire.altitudeValid = fix.verticalAccuracy >= 0
        sequence &+= 1; wire.sequence = sequence
        var bytes = [UInt8](repeating: 0, count: Int(EI_PACKET_SIZE))
        let valid = bytes.withUnsafeMutableBufferPointer { buffer in
            EIEncodePosition(wire, buffer.baseAddress, buffer.count)
        }
        guard valid else { pendingFix = nil; return }
        // Never split a position packet. The receiver rejects non-21-byte writes.
        guard peripheral.maximumWriteValueLength(for: .withResponse) >= bytes.count else {
            failConnection("Bluetooth cannot write the required 21-byte packet. Reconnect the reader.")
            return
        }
        pendingFix = nil; inFlight = true; writeStarted = now; sentAt = now; sentFix = fix
        peripheral.writeValue(Data(bytes), for: characteristic, type: .withResponse)
    }
}

extension GPSBridge: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if sharing, let selected, reconnectUntil != nil {
                status = "Reconnecting"; central.connect(selected, options: nil)
            } else { scanIfReady() }
        case .poweredOff:
            timeout?.cancel(); wantsScan = false
            stopSharing(); disconnectLink(); scanning = false
            status = "Bluetooth is off"; detail = "Turn on Bluetooth, then search again."
        case .unauthorized:
            timeout?.cancel()
            stopSharing(); disconnectLink(); scanning = false; wantsScan = false; needsSettings = true
            status = "Bluetooth access is denied"; detail = "Allow Bluetooth access for this app in Settings."
        case .unsupported:
            failConnection("Bluetooth LE is unavailable. Use a physical iPhone, not the simulator.")
        case .resetting, .unknown:
            status = "Bluetooth is initializing"
        @unknown default: status = "Bluetooth is unavailable"
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard scanning else { return }
        peripherals[peripheral.identifier] = peripheral
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            ?? peripheral.name ?? "ExplorInk reader"
        if let index = readers.firstIndex(where: { $0.id == peripheral.identifier }) {
            readers[index].signal = RSSI.intValue
        } else {
            readers.append(Reader(id: peripheral.identifier, name: name, signal: RSSI.intValue))
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == selected?.identifier else { central.cancelPeripheralConnection(peripheral); return }
        position = nil; inFlight = false; pendingFix = nil; sentAt = nil; sentFix = nil
        writeFailures = 0
        peripheral.delegate = self
        peripheral.discoverServices([serviceID])
        armTimeout(seconds: 15) { [weak self] in self?.failConnection("Position service discovery timed out.") }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == selected?.identifier else { return }
        failConnection(error?.localizedDescription ?? "Could not connect. Keep Explore open and try again.")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == selected?.identifier else { return }
        connected = false; position = nil; inFlight = false; pendingFix = nil; sentFix = nil; sentAt = nil
        event("Bluetooth disconnected")
        if sharing && central.state == .poweredOn {
            // Keep the user-started location session alive briefly so iOS can
            // deliver reconnect callbacks while locked. Bound this to 2 min.
            reconnectUntil = Date().addingTimeInterval(120)
            connecting = true; status = "Reconnecting to your reader"
            detail = "GPS stays active for up to two minutes while reconnecting."
            central.connect(peripheral, options: nil)
            armTimeout(seconds: 120) { [weak self] in
                self?.failConnection("The reader is out of reach. Location sharing has stopped.")
            }
        } else {
            failConnection("Reader disconnected. Open Explore and reconnect.")
        }
    }
}

extension GPSBridge: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral.identifier == selected?.identifier else { return }
        guard error == nil, let service = peripheral.services?.first(where: { $0.uuid == serviceID }) else {
            failConnection("This reader did not expose the ExplorInk position service."); return
        }
        peripheral.discoverCharacteristics([positionID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral.identifier == selected?.identifier else { return }
        guard error == nil, let characteristic = service.characteristics?.first(where: { $0.uuid == positionID }),
              characteristic.properties.contains(.write) else {
            failConnection("The position characteristic does not support acknowledged writes."); return
        }
        timeout?.cancel(); position = characteristic; connected = true; connecting = false; reconnectUntil = nil
        status = sharing ? "Reconnected · waiting for a fresh location" : "Reader connected"
        detail = sharing ? "Only a new location fix will be sent." : "Tap Start sharing when you are ready."
        event("Position service connected")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral.identifier == selected?.identifier, characteristic.uuid == positionID, inFlight else { return }
        inFlight = false; writeStarted = nil
        guard sharing else { return }
        if let error {
            writeFailures += 1; event("Write failed: \(error.localizedDescription)")
            status = "Location write failed"; detail = "Waiting for the next fresh fix."
            if writeFailures >= 3 { failConnection("Three location writes failed. Reconnect the reader.") }
        } else {
            writeFailures = 0; lastAcknowledged = Date(); acknowledgedCount += 1
            status = "Sharing location"
            detail = "You can lock your phone. Keep this app running."
        }
    }
}

extension GPSBridge: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard sharing else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: beginLocation()
        case .denied, .restricted: locationDenied()
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard sharing else { return }
        if let deadline = reconnectUntil, Date() >= deadline {
            failConnection("Reconnection timed out; location sharing has stopped."); return
        }
        guard let fix = locations.last, CLLocationCoordinate2DIsValid(fix.coordinate),
              fix.horizontalAccuracy.isFinite, fix.horizontalAccuracy >= 0,
              Date().timeIntervalSince(fix.timestamp) <= 10,
              Date().timeIntervalSince(fix.timestamp) >= -2 else { return }
        guard lastFix == nil || fix.timestamp > lastFix!.timestamp else { return }
        lastFix = fix
        if fix.horizontalAccuracy > 100 {
            pendingFix = nil; status = "Location is too approximate"
            detail = "Waiting for accuracy within 100 metres. Enable Precise Location if it is off."
            return
        }
        // Drop fixes acquired while disconnected. Reconnection needs a new fix.
        if connected { pendingFix = fix; sendIfReady() }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied { locationDenied(); return }
        guard sharing else { return }
        pendingFix = nil; status = "Location temporarily unavailable"
        detail = "Waiting for GPS to recover. The reader may retain its last position."
        event("Location error: \(error.localizedDescription)")
    }
}
