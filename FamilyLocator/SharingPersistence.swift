import CoreLocation
import Foundation

struct LocationSample: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    var accuracy: Double
    var timestamp: Date

    init(_ location: CLLocation, precise: Bool = true) {
        latitude = precise ? location.coordinate.latitude : (location.coordinate.latitude * 100).rounded() / 100
        longitude = precise ? location.coordinate.longitude : (location.coordinate.longitude * 100).rounded() / 100
        accuracy = precise ? location.horizontalAccuracy : max(1500, location.horizontalAccuracy)
        timestamp = location.timestamp
    }

    var location: CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), altitude: 0,
                   horizontalAccuracy: accuracy, verticalAccuracy: -1, timestamp: timestamp)
    }

    func isUsable(at now: Date) -> Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude) && accuracy >= 0 &&
        timestamp <= now.addingTimeInterval(30) && now.timeIntervalSince(timestamp) <= 300
    }
}

struct ArrivalState: Codable {
    var anchor: LocationSample
    var arrivedAt: Date

    mutating func observe(_ sample: LocationSample) {
        // Compare against the arrival anchor, never the previous GPS fix: slow movement must count.
        if sample.location.distance(from: anchor.location) > max(100, sample.accuracy, anchor.accuracy) ||
            sample.timestamp.timeIntervalSince(anchor.timestamp) > 600 {
            arrivedAt = sample.timestamp
            anchor = sample
        } else {
            anchor.timestamp = sample.timestamp
        }
    }
}

struct PendingLocation: Codable, Equatable {
    var id = UUID()
    var scope: CircleScope
    var accountID: String
    var displayName: String
    var sample: LocationSample
    var arrivedAt: Date
    var expiresAt: Date?
}

struct PendingRemoval: Codable, Equatable {
    var scope: CircleScope
    var accountID: String
}

struct SharingState: Codable {
    var scope: CircleScope?
    var accountID: String?
    var pendingInvite: URL?
    var pendingLocation: PendingLocation?
    var removals: [PendingRemoval] = []
    var arrival: ArrivalState?
    var restoreAllowed: Bool?
}

struct SharingPersistence {
    var url: URL

    static var standard: SharingPersistence {
        SharingPersistence(url: URL.applicationSupportDirectory.appending(path: "Whereabouts/sharing-state.json"))
    }

    func load() throws -> SharingState {
        guard FileManager.default.fileExists(atPath: url.path) else { return SharingState() }
        return try JSONDecoder().decode(SharingState.self, from: Data(contentsOf: url))
    }

    func save(_ state: SharingState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var excludedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try excludedURL.setResourceValues(values)
    }
}
