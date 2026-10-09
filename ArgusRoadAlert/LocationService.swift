import CoreLocation

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let mgr = CLLocationManager()
    @Published var location: CLLocation?
    @Published var running = false
    var onUpdate: ((CLLocation) -> Void)?

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyBest
        mgr.activityType = .automotiveNavigation
        mgr.allowsBackgroundLocationUpdates = true
        mgr.pausesLocationUpdatesAutomatically = false
        mgr.showsBackgroundLocationIndicator = true
    }
    func start() { mgr.requestAlwaysAuthorization(); mgr.startUpdatingLocation(); running = true }
    func stop() { mgr.stopUpdatingLocation(); running = false }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        DispatchQueue.main.async { self.location = l; self.onUpdate?(l) }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
    }
}
