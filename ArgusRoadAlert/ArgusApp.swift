import SwiftUI
import CoreLocation

@MainActor
final class AppModel: ObservableObject {
    let loc = LocationService()
    let store = CameraStore()
    let alerts = AlertEngine()
    init() {
        loc.onUpdate = { [weak self] l in
            Task { @MainActor in
                guard let self else { return }
                self.store.prune()
                await self.store.refreshIfNeeded(near: l)
                self.alerts.evaluate(l, cameras: self.store.cameras)
            }
        }
    }
}

@main
struct ArgusApp: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model.loc)
                .environmentObject(model.store)
                .environmentObject(model.alerts)
        }
    }
}
