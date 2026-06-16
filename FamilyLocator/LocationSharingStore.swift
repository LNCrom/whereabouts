import CoreLocation
import Foundation

@MainActor
final class LocationSharingStore: NSObject, ObservableObject {
    enum SharingWindow: String, CaseIterable, Identifiable {
        case oneHour = "1 hour"
        case tonight = "Until tonight"
        case always = "Always"

        var id: String { rawValue }
    }

    @Published var isLiveSharingEnabled = true {
        didSet { updateLocationServices() }
    }

    @Published var driveDetectionEnabled = true
    @Published var lowBatteryAlertsEnabled = true
    @Published var sharingWindow: SharingWindow = .always
    @Published var allowsPreciseSharing = true {
        didSet { updateLocationServices() }
    }

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var lastLocationUpdate: Date?
    @Published private(set) var locationErrorMessage: String?

    private let locationManager = CLLocationManager()

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .otherNavigation
        locationManager.pausesLocationUpdatesAutomatically = true
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var canShareLocation: Bool {
        isLiveSharingEnabled && authorizationStatus.allowsLocationUse
    }

    var permissionSummary: String {
        switch authorizationStatus {
        case .notDetermined:
            return "Not requested"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorizedWhenInUse:
            return "When in use"
        case .authorizedAlways:
            return "Always"
        @unknown default:
            return "Unknown"
        }
    }

    var sharingSummary: String {
        guard isLiveSharingEnabled else { return "Paused" }
        guard authorizationStatus.allowsLocationUse else { return permissionSummary }
        return allowsPreciseSharing ? "Sharing precise location" : "Sharing approximate location"
    }

    var lastUpdatedSummary: String {
        guard let lastLocationUpdate else { return "No location yet" }
        return lastLocationUpdate.formatted(.relative(presentation: .named))
    }

    var coordinateSummary: String {
        guard let coordinate = currentLocation?.coordinate else { return "Waiting for this device" }
        return "\(coordinate.latitude.formatted(.number.precision(.fractionLength(4)))), \(coordinate.longitude.formatted(.number.precision(.fractionLength(4))))"
    }

    func requestWhenInUsePermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    func refreshCurrentLocation() {
        guard authorizationStatus.allowsLocationUse else {
            requestWhenInUsePermission()
            return
        }

        locationErrorMessage = nil
        locationManager.requestLocation()
    }

    private func updateLocationServices() {
        locationManager.desiredAccuracy = allowsPreciseSharing ? kCLLocationAccuracyBest : kCLLocationAccuracyKilometer

        guard isLiveSharingEnabled, authorizationStatus.allowsLocationUse else {
            locationManager.stopUpdatingLocation()
            return
        }

        locationManager.startUpdatingLocation()
    }
}

extension LocationSharingStore: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            updateLocationServices()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            currentLocation = location
            lastLocationUpdate = Date()
            locationErrorMessage = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationErrorMessage = error.localizedDescription
        }
    }
}

private extension CLAuthorizationStatus {
    var allowsLocationUse: Bool {
        switch self {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .denied, .notDetermined, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
