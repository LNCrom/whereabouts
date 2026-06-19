import CloudKit
import CoreLocation
import Foundation
import UIKit

@MainActor
final class CloudLocationSharingStore: ObservableObject {
    @Published private(set) var circleCode: String?
    @Published private(set) var remoteMembers: [FamilyMember] = []
    @Published private(set) var statusMessage = "Create or accept a Whereabouts invite to start shared locations."
    @Published private(set) var isFetching = false

    private let container = CKContainer(identifier: "iCloud.com.lancecromwell.Whereabouts")
    private let database: CKDatabase
    private let defaults: UserDefaults
    private let geocoder = CLGeocoder()

    private var deviceID: String {
        if let stored = defaults.string(forKey: "whereabouts.deviceID") {
            return stored
        }

        let newValue = UUID().uuidString
        defaults.set(newValue, forKey: "whereabouts.deviceID")
        return newValue
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        database = container.publicCloudDatabase
        circleCode = defaults.string(forKey: "whereabouts.circleCode")
    }

    var hasActiveCircle: Bool {
        circleCode?.isEmpty == false
    }

    var inviteURL: URL {
        let code = circleCode ?? createCircle()
        return URL(string: "whereabouts://join?circle=\(code)")!
    }

    func createCircle() -> String {
        if let circleCode {
            return circleCode
        }

        let code = UUID().uuidString
        setCircle(code)
        statusMessage = "Invite ready. Send it to someone you trust."
        return code
    }

    func acceptInvite(from url: URL) {
        guard url.scheme == "whereabouts",
              url.host == "join",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "circle" })?.value,
              code.isEmpty == false
        else {
            statusMessage = "That invite link was not recognized."
            return
        }

        setCircle(code)
        statusMessage = "Invite accepted. Turn on location sharing to appear in this circle."
    }

    func publish(location: CLLocation, displayName: String? = nil) {
        guard let circleCode, circleCode.isEmpty == false else { return }

        let resolvedDisplayName = displayName ?? UIDevice.current.name
        let resolvedDeviceID = deviceID

        #if DEBUG
        if publishToLocalTestTransport(
            circleCode: circleCode,
            deviceID: resolvedDeviceID,
            displayName: resolvedDisplayName,
            location: location
        ) {
            return
        }
        #endif

        let recordID = CKRecord.ID(recordName: "location-\(circleCode)-\(deviceID)")
        database.fetch(withRecordID: recordID) { [weak self] existingRecord, _ in
            guard let self else { return }

            let record = existingRecord ?? CKRecord(recordType: "WhereaboutsLocation", recordID: recordID)
            record["circleCode"] = circleCode as CKRecordValue
            record["deviceID"] = resolvedDeviceID as CKRecordValue
            record["displayName"] = resolvedDisplayName as CKRecordValue
            record["latitude"] = location.coordinate.latitude as CKRecordValue
            record["longitude"] = location.coordinate.longitude as CKRecordValue
            record["horizontalAccuracy"] = location.horizontalAccuracy as CKRecordValue
            record["updatedAt"] = Date() as CKRecordValue

            self.database.save(record) { _, error in
                Task { @MainActor in
                    if let error {
                        self.statusMessage = "Could not publish this device location: \(error.localizedDescription)"
                    } else {
                        self.statusMessage = "This device location is shared with your Whereabouts circle."
                    }
                }
            }
        }
    }

    func fetchSharedLocations() {
        guard let circleCode, circleCode.isEmpty == false else {
            remoteMembers = []
            statusMessage = "No Whereabouts circle yet."
            return
        }

        #if DEBUG
        if fetchFromLocalTestTransport(circleCode: circleCode) {
            return
        }
        #endif

        isFetching = true

        let predicate = NSPredicate(format: "circleCode == %@ AND deviceID != %@", circleCode, deviceID)
        let query = CKQuery(recordType: "WhereaboutsLocation", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]

        var records: [CKRecord] = []
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 25
        operation.recordMatchedBlock = { _, result in
            if case let .success(record) = result {
                records.append(record)
            }
        }
        operation.queryResultBlock = { [weak self] result in
            Task { @MainActor in
                guard let self else { return }

                self.isFetching = false

                switch result {
                case .success:
                    self.remoteMembers = records.compactMap(self.member(from:))
                    self.statusMessage = self.remoteMembers.isEmpty
                        ? "No one has accepted and published a Whereabouts location yet."
                        : "Loaded \(self.remoteMembers.count) shared location\(self.remoteMembers.count == 1 ? "" : "s")."
                case .failure(let error):
                    self.statusMessage = "Could not load shared locations: \(error.localizedDescription)"
                }
            }
        }

        database.add(operation)
    }

    private func setCircle(_ code: String) {
        circleCode = code
        defaults.set(code, forKey: "whereabouts.circleCode")
    }

    private func member(from record: CKRecord) -> FamilyMember? {
        guard let name = record["displayName"] as? String,
              let latitude = record["latitude"] as? Double,
              let longitude = record["longitude"] as? Double
        else {
            return nil
        }

        let updatedAt = record["updatedAt"] as? Date ?? Date()
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)

        return FamilyMember(
            name: name,
            phoneNumber: nil,
            emailAddress: nil,
            device: "iPhone",
            status: .live,
            place: "Live shared location",
            address: "\(coordinate.latitude.formatted(.number.precision(.fractionLength(5)))), \(coordinate.longitude.formatted(.number.precision(.fractionLength(5))))",
            batteryLevel: 0,
            updatedAt: updatedAt.formatted(.relative(presentation: .named)),
            arrivedAt: updatedAt,
            lastLocationUpdate: updatedAt,
            isLocationShared: true,
            tint: .green,
            latitude: latitude,
            longitude: longitude,
            speed: nil,
            eta: nil
        )
    }
}

#if DEBUG
private extension CloudLocationSharingStore {
    var localTestTransportURL: URL? {
        guard let path = ProcessInfo.processInfo.environment["WHEREABOUTS_LOCAL_SHARING_FILE"],
              path.isEmpty == false
        else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }

    func publishToLocalTestTransport(
        circleCode: String,
        deviceID: String,
        displayName: String,
        location: CLLocation
    ) -> Bool {
        guard let localTestTransportURL else { return false }

        do {
            var records = try loadLocalTestRecords(from: localTestTransportURL)
            records.removeAll { $0.circleCode == circleCode && $0.deviceID == deviceID }
            records.append(
                LocalSharedLocationRecord(
                    circleCode: circleCode,
                    deviceID: deviceID,
                    displayName: displayName,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    horizontalAccuracy: location.horizontalAccuracy,
                    updatedAt: Date()
                )
            )
            try saveLocalTestRecords(records, to: localTestTransportURL)
            statusMessage = "This device location is shared with your local test circle."
        } catch {
            statusMessage = "Could not publish local test location: \(error.localizedDescription)"
        }

        return true
    }

    func fetchFromLocalTestTransport(circleCode: String) -> Bool {
        guard let localTestTransportURL else { return false }

        do {
            let records = try loadLocalTestRecords(from: localTestTransportURL)
            remoteMembers = records
                .filter { $0.circleCode == circleCode && $0.deviceID != deviceID }
                .map(member(from:))
            statusMessage = remoteMembers.isEmpty
                ? "No one has published a local test location yet."
                : "Loaded \(remoteMembers.count) local test shared location\(remoteMembers.count == 1 ? "" : "s")."
        } catch {
            remoteMembers = []
            statusMessage = "Could not load local test locations: \(error.localizedDescription)"
        }

        return true
    }

    func loadLocalTestRecords(from url: URL) throws -> [LocalSharedLocationRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([LocalSharedLocationRecord].self, from: data)
    }

    func saveLocalTestRecords(_ records: [LocalSharedLocationRecord], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(records)
        try data.write(to: url, options: .atomic)
    }

    func member(from record: LocalSharedLocationRecord) -> FamilyMember {
        FamilyMember(
            name: record.displayName,
            phoneNumber: nil,
            emailAddress: nil,
            device: "iPhone",
            status: .live,
            place: "Live shared location",
            address: "\(record.latitude.formatted(.number.precision(.fractionLength(5)))), \(record.longitude.formatted(.number.precision(.fractionLength(5))))",
            batteryLevel: 0,
            updatedAt: record.updatedAt.formatted(.relative(presentation: .named)),
            arrivedAt: record.updatedAt,
            lastLocationUpdate: record.updatedAt,
            isLocationShared: true,
            tint: .green,
            latitude: record.latitude,
            longitude: record.longitude,
            speed: nil,
            eta: nil
        )
    }
}

private struct LocalSharedLocationRecord: Codable {
    var circleCode: String
    var deviceID: String
    var displayName: String
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var updatedAt: Date
}
#endif
