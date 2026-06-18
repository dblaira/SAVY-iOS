import Foundation
import CoreLocation

/// One-shot current-place lookup for the Location part ("Use current location"). Best-effort:
/// if permission is denied or it fails, the user can still type a location by hand.
@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isResolving = false
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<String?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentPlaceName() async -> String? {
        if continuation != nil { return nil }   // already resolving
        isResolving = true
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        return await withCheckedContinuation { cont in
            self.continuation = cont
            self.manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { Task { @MainActor in self.finish(nil) }; return }
        CLGeocoder().reverseGeocodeLocation(loc) { placemarks, _ in
            let p = placemarks?.first
            let name = [p?.name, p?.subLocality, p?.locality].compactMap { $0 }.first
            Task { @MainActor in self.finish(name) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    private func finish(_ value: String?) {
        isResolving = false
        continuation?.resume(returning: value)
        continuation = nil
    }
}
