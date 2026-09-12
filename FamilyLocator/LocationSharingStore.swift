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

    @Published var isLiveSharingEnabled: Bool {
        didSet {
            defaults.set(isLiveSharingEnabled, forKey: Keys.liveSharing)
            if isLiveSharingEnabled { updateExpiration() }
            updateLocationServices()
        }
    }

    @Published var sharingWindow: SharingWindow {
        didSet {
            defaults.set(sharingWindow.rawValue, forKey: Keys.sharingWindow)
            if isLiveSharingEnabled { updateExpiration() }
        }
    }
    @Published var allowsPreciseSharing: Bool {
        didSet {
            defaults.set(allowsPreciseSharing, forKey: Keys.preciseSharing)
            updateLocationServices()
        }
    }

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var lastLocationUpdate: Date?
    @Published private(set) var locationErrorMessage: String?

    private let locationManager = CLLocationManager()
    private let defaults: UserDefaults
    private var sessionActive = false

    private enum Keys {
        static let liveSharing = "whereabouts.location.liveSharing"
        static let preciseSharing = "whereabouts.location.preciseSharing"
        static let sharingWindow = "whereabouts.location.sharingWindow"
        static let sharingExpiresAt = "whereabouts.location.sharingExpiresAt"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isLiveSharingEnabled = defaults.object(forKey: Keys.liveSharing) as? Bool ?? false
        allowsPreciseSharing = defaults.object(forKey: Keys.preciseSharing) as? Bool ?? true
        sharingWindow = SharingWindow(rawValue: defaults.string(forKey: Keys.sharingWindow) ?? "") ?? .always
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .otherNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        enforceSharingExpiration()
        updateLocationServices()
    }

    var canShareLocation: Bool {
        sessionActive && isLiveSharingEnabled && authorizationStatus.allowsLocationUse
    }

    var sharingExpiresAt: Date? { defaults.object(forKey: Keys.sharingExpiresAt) as? Date }

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

    func enableSharing() {
        isLiveSharingEnabled = true
        if authorizationStatus == .notDetermined { requestWhenInUsePermission() }
        else { refreshCurrentLocation(requestPermission: false) }
    }

    func requestAlwaysPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    func refreshCurrentLocation(requestPermission: Bool = true) {
        enforceSharingExpiration()
        guard authorizationStatus.allowsLocationUse else {
            if requestPermission { requestWhenInUsePermission() }
            return
        }

        locationErrorMessage = nil
        locationManager.requestLocation()
    }

    func setSessionActive(_ active: Bool) {
        guard sessionActive != active else { return }
        sessionActive = active
        updateLocationServices()
    }

    func stopSharing() {
        isLiveSharingEnabled = false
        defaults.removeObject(forKey: Keys.sharingExpiresAt)
    }

    func enforceSharingExpiration(now: Date = Date()) {
        guard isLiveSharingEnabled,
              let expiresAt = defaults.object(forKey: Keys.sharingExpiresAt) as? Date,
              expiresAt <= now
        else { return }
        stopSharing()
        locationErrorMessage = "Location sharing ended at the selected time."
    }

    private func updateExpiration(now: Date = Date()) {
        let expiration: Date?
        switch sharingWindow {
        case .oneHour:
            expiration = now.addingTimeInterval(60 * 60)
        case .tonight:
            expiration = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: now)
        case .always:
            expiration = nil
        }

        if let expiration {
            defaults.set(expiration, forKey: Keys.sharingExpiresAt)
        } else {
            defaults.removeObject(forKey: Keys.sharingExpiresAt)
        }
    }

    private func updateLocationServices() {
        locationManager.desiredAccuracy = allowsPreciseSharing ? kCLLocationAccuracyBest : kCLLocationAccuracyKilometer
        locationManager.distanceFilter = 25
        locationManager.allowsBackgroundLocationUpdates = authorizationStatus == .authorizedAlways && isLiveSharingEnabled && sessionActive

        guard sessionActive, isLiveSharingEnabled, authorizationStatus.allowsLocationUse else {
            locationManager.stopUpdatingLocation()
            locationManager.stopMonitoringSignificantLocationChanges()
            locationManager.stopMonitoringVisits()
            return
        }

        locationManager.startUpdatingLocation()
        if authorizationStatus == .authorizedAlways {
            locationManager.startMonitoringSignificantLocationChanges()
            locationManager.startMonitoringVisits()
        }
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
            enforceSharingExpiration()
            guard location.horizontalAccuracy >= 0, abs(location.timestamp.timeIntervalSinceNow) < 300 else { return }
            currentLocation = location
            lastLocationUpdate = location.timestamp
            locationErrorMessage = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationErrorMessage = error.localizedDescription
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in
            enforceSharingExpiration()
            if canShareLocation { refreshCurrentLocation(requestPermission: false) }
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
