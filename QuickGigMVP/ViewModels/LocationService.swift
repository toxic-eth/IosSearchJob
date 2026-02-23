import Foundation
import CoreLocation

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var lastLocationError: String?

    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
    }

    func requestPermission() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            manager.startUpdatingLocation()
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last?.coordinate
        lastLocationError = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == kCLErrorDomain,
           nsError.code == CLError.locationUnknown.rawValue {
            // Temporary condition, keep service alive and wait for next update.
            return
        }
        lastLocationError = error.localizedDescription
    }
}

enum UkraineRegion {
    static let center = CLLocationCoordinate2D(latitude: 50.4501, longitude: 30.5234)

    static func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let latRange = 44.0...52.7
        let lonRange = 22.0...40.3
        return latRange.contains(coordinate.latitude) && lonRange.contains(coordinate.longitude)
    }
}
