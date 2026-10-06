import SwiftUI

@main
struct ExplorInkGPSApp: App {
    @StateObject private var bridge = GPSBridge()
    var body: some Scene {
        WindowGroup { ContentView(bridge: bridge) }
    }
}
