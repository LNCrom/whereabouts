import CloudKit
import CoreLocation
import Foundation
import UIKit

@MainActor
final class CloudLocationSharingStore: ObservableObject {
    static let acceptedShareMetadataNotification = Notification.Name("WhereaboutsAcceptedCloudKitShare")

    @Published private(set) var remoteMembers: [FamilyMember] = []
    @Published private(set) var statusMessage = "Create or accept a Whereabouts invite to start shared locations."
    @Published private(set) var isFetching = false
    @Published private(set) var isPreparingShare = false

    private enum Constants {
        static let containerIdentifier = "iCloud.com.lancecromwell.Whereabouts"
        static let zoneName = "WhereaboutsFamilyCircle"
        static let locationRecordType = "WhereaboutsLocation"
    }

    private enum Keys {
        static let privateZoneName = "whereabouts.cloud.privateZoneName"
        static let sharedZoneName = "whereabouts.cloud.sharedZoneName"
        static let sharedZoneOwnerName = "whereabouts.cloud.sharedZoneOwnerName"
        static let currentUserRecordName = "whereabouts.cloud.currentUserRecordName"
    }

    private enum CircleScope {
        case owner(CKRecordZone.ID)
        case participant(CKRecordZone.ID)

        var zoneID: CKRecordZone.ID {
            switch self {
            case .owner(let zoneID), .participant(let zoneID):
                return zoneID
            }
        }

        var isOwner: Bool {
            if case .owner = self { return true }
            return false
        }
    }

    private let container = CKContainer(identifier: Constants.containerIdentifier)
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase
    private let defaults: UserDefaults

    private var shareObserver: NSObjectProtocol?
    private var lastPublishedLocation: CLLocation?
    private var lastPublishedAt: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        privateDatabase = container.privateCloudDatabase
        sharedDatabase = container.sharedCloudDatabase

        shareObserver = NotificationCenter.default.addObserver(
            forName: Self.acceptedShareMetadataNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let metadata = notification.object as? CKShare.Metadata else { return }
            Task { @MainActor in
                self?.acceptShare(metadata)
            }
        }

        if let pendingMetadata = AppDelegate.consumePendingShareMetadata() {
            acceptShare(pendingMetadata)
        }

        updateAccountStatus()
    }

    deinit {
        if let shareObserver {
            NotificationCenter.default.removeObserver(shareObserver)
        }
    }

    var hasActiveCircle: Bool {
        if activeScope != nil {
            return true
        }

        #if DEBUG
        return localTestTransportURL != nil
        #else
        return false
        #endif
    }

    var sharingTitle: String {
        activeScope?.isOwner == true ? "Manage Whereabouts sharing" : "Create Whereabouts sharing"
    }

    func updateAccountStatus() {
        container.accountStatus { [weak self] status, error in
            Task { @MainActor in
                guard let self else { return }

                if let error {
                    self.statusMessage = "Could not check iCloud account: \(error.localizedDescription)"
                    return
                }

                switch status {
                case .available:
                    self.statusMessage = self.activeScope == nil
                        ? "iCloud is ready. Create or accept a Whereabouts share."
                        : "iCloud sharing is ready."
                    self.cacheCurrentUserRecordID()
                case .noAccount:
                    self.statusMessage = "Sign in to iCloud on this iPhone to use Whereabouts sharing."
                case .restricted:
                    self.statusMessage = "iCloud is restricted on this iPhone."
                case .couldNotDetermine:
                    self.statusMessage = "Whereabouts could not determine iCloud account status."
                case .temporarilyUnavailable:
                    self.statusMessage = "iCloud is temporarily unavailable. Try again soon."
                @unknown default:
                    self.statusMessage = "Whereabouts could not determine iCloud account status."
                }
            }
        }
    }

    func configure(_ controller: UICloudSharingController) {
        controller.delegate = CloudSharingDelegate.shared
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.modalPresentationStyle = .formSheet
    }

    func prepareShare(
        _ controller: UICloudSharingController,
        completion: @escaping (CKShare?, CKContainer?, Error?) -> Void
    ) {
        prepareShare { result in
            switch result {
            case .success(let preparedShare):
                completion(preparedShare.share, preparedShare.container, nil)
            case .failure(let error):
                completion(nil, self.container, error)
            }
        }
    }

    func prepareShare(completion: @escaping (Result<(share: CKShare, container: CKContainer), Error>) -> Void) {
        isPreparingShare = true
        statusMessage = "Preparing secure iCloud share..."

        ensureOwnerZone { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let zoneID):
                self.fetchOrCreateZoneShare(in: zoneID) { result in
                    Task { @MainActor in
                        self.isPreparingShare = false

                        switch result {
                        case .success(let share):
                            self.statusMessage = "Secure iCloud invite ready."
                            completion(.success((share, self.container)))
                        case .failure(let error):
                            self.statusMessage = "Could not create iCloud share: \(error.localizedDescription)"
                            completion(.failure(error))
                        }
                    }
                }
            case .failure(let error):
                Task { @MainActor in
                    self.isPreparingShare = false
                    self.statusMessage = "Could not prepare iCloud share: \(error.localizedDescription)"
                    completion(.failure(error))
                }
            }
        }
    }

    func acceptShare(_ metadata: CKShare.Metadata) {
        statusMessage = "Accepting Whereabouts share..."

        let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
        operation.acceptSharesResultBlock = { [weak self] result in
            Task { @MainActor in
                guard let self else { return }

                if case .failure(let error) = result {
                    self.statusMessage = "Could not accept Whereabouts share: \(error.localizedDescription)"
                    return
                }

                let zoneID = metadata.share.recordID.zoneID
                self.defaults.set(zoneID.zoneName, forKey: Keys.sharedZoneName)
                self.defaults.set(zoneID.ownerName, forKey: Keys.sharedZoneOwnerName)
                self.statusMessage = "Whereabouts share accepted. Turn on location permission to appear in this circle."
                self.fetchSharedLocations()
            }
        }

        container.add(operation)
    }

    func publish(location: CLLocation, displayName: String? = nil) {
        guard shouldPublish(location) else { return }

        #if DEBUG
        if publishToLocalTestTransport(
            circleCode: "local-test-circle",
            deviceID: currentDeviceRecordNameFallback,
            displayName: displayName ?? UIDevice.current.name,
            location: location
        ) {
            return
        }
        #endif

        guard let scope = activeScope else {
            statusMessage = "Create or accept a Whereabouts share before publishing location."
            return
        }

        resolveCurrentUserRecordName { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let userRecordName):
                let database = self.database(for: scope)
                let recordID = CKRecord.ID(recordName: "location-\(userRecordName)", zoneID: scope.zoneID)
                database.fetch(withRecordID: recordID) { existingRecord, _ in
                    let record = existingRecord ?? CKRecord(recordType: Constants.locationRecordType, recordID: recordID)
                    let arrivedAt = Self.arrivalDate(for: location, existingRecord: existingRecord)

                    Self.resolveAddress(for: location) { address in
                        record["userRecordName"] = userRecordName as CKRecordValue
                        record["displayName"] = (displayName ?? UIDevice.current.name) as CKRecordValue
                        record["latitude"] = location.coordinate.latitude as CKRecordValue
                        record["longitude"] = location.coordinate.longitude as CKRecordValue
                        record["horizontalAccuracy"] = location.horizontalAccuracy as CKRecordValue
                        record["address"] = address as CKRecordValue
                        record["arrivedAt"] = arrivedAt as CKRecordValue
                        record["updatedAt"] = Date() as CKRecordValue

                        database.save(record) { _, error in
                            Task { @MainActor in
                                if let error {
                                    self.statusMessage = "Could not publish this device location: \(error.localizedDescription)"
                                } else {
                                    self.markPublished(location)
                                    self.statusMessage = "This device location is shared with your Whereabouts circle."
                                    self.fetchSharedLocations()
                                }
                            }
                        }
                    }
                }
            case .failure(let error):
                Task { @MainActor in
                    self.statusMessage = "Could not identify iCloud user: \(error.localizedDescription)"
                }
            }
        }
    }

    func fetchSharedLocations() {
        #if DEBUG
        if fetchFromLocalTestTransport(circleCode: "local-test-circle") {
            return
        }
        #endif

        guard let scope = activeScope else {
            remoteMembers = []
            statusMessage = "No Whereabouts share yet."
            return
        }

        isFetching = true

        resolveCurrentUserRecordName { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let userRecordName):
                let query = CKQuery(recordType: Constants.locationRecordType, predicate: NSPredicate(value: true))

                var records: [CKRecord] = []
                let operation = CKQueryOperation(query: query)
                operation.zoneID = scope.zoneID
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
                            let visibleRecords = records
                                .filter { ($0["userRecordName"] as? String) != userRecordName }
                                .sorted {
                                    (($0["updatedAt"] as? Date) ?? .distantPast) >
                                        (($1["updatedAt"] as? Date) ?? .distantPast)
                                }
                            self.remoteMembers = visibleRecords.compactMap(self.member(from:))
                            self.statusMessage = self.remoteMembers.isEmpty
                                ? "No one has accepted and published a Whereabouts location yet."
                                : "Loaded \(self.remoteMembers.count) shared location\(self.remoteMembers.count == 1 ? "" : "s")."
                        case .failure(let error):
                            self.statusMessage = "Could not load shared locations: \(error.localizedDescription)"
                        }
                    }
                }

                self.database(for: scope).add(operation)
            case .failure(let error):
                Task { @MainActor in
                    self.isFetching = false
                    self.statusMessage = "Could not identify iCloud user: \(error.localizedDescription)"
                }
            }
        }
    }

    private var activeScope: CircleScope? {
        if let privateZoneName = defaults.string(forKey: Keys.privateZoneName), privateZoneName.isEmpty == false {
            return .owner(CKRecordZone.ID(zoneName: privateZoneName, ownerName: CKCurrentUserDefaultName))
        }

        if let sharedZoneName = defaults.string(forKey: Keys.sharedZoneName),
           let ownerName = defaults.string(forKey: Keys.sharedZoneOwnerName),
           sharedZoneName.isEmpty == false,
           ownerName.isEmpty == false {
            return .participant(CKRecordZone.ID(zoneName: sharedZoneName, ownerName: ownerName))
        }

        return nil
    }

    private func database(for scope: CircleScope) -> CKDatabase {
        scope.isOwner ? privateDatabase : sharedDatabase
    }

    private func ensureOwnerZone(completion: @escaping (Result<CKRecordZone.ID, Error>) -> Void) {
        let zoneID = CKRecordZone.ID(zoneName: Constants.zoneName, ownerName: CKCurrentUserDefaultName)
        privateDatabase.fetch(withRecordZoneID: zoneID) { [weak self] zone, error in
            guard let self else { return }

            if zone != nil {
                Task { @MainActor in
                    self.defaults.set(zoneID.zoneName, forKey: Keys.privateZoneName)
                    completion(.success(zoneID))
                }
                return
            }

            if let ckError = error as? CKError, ckError.code != .zoneNotFound, ckError.code != .unknownItem {
                completion(.failure(ckError))
                return
            }

            let zone = CKRecordZone(zoneID: zoneID)
            self.privateDatabase.save(zone) { [weak self] _, error in
                guard let self else { return }

                if let ckError = error as? CKError, ckError.code != .serverRecordChanged {
                    completion(.failure(ckError))
                    return
                }

                Task { @MainActor in
                    self.defaults.set(zoneID.zoneName, forKey: Keys.privateZoneName)
                    completion(.success(zoneID))
                }
            }
        }
    }

    private func fetchOrCreateZoneShare(
        in zoneID: CKRecordZone.ID,
        completion: @escaping (Result<CKShare, Error>) -> Void
    ) {
        let recordID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        privateDatabase.fetch(withRecordID: recordID) { [weak self] record, error in
            guard let self else { return }

            if let share = record as? CKShare {
                completion(.success(share))
                return
            }

            if let ckError = error as? CKError, ckError.code != .unknownItem {
                completion(.failure(ckError))
                return
            }

            let share = CKShare(recordZoneID: zoneID)
            share[CKShare.SystemFieldKey.title] = "Whereabouts Family Circle" as CKRecordValue
            share.publicPermission = .none

            self.privateDatabase.save(share) { savedRecord, error in
                if let share = savedRecord as? CKShare {
                    completion(.success(share))
                } else {
                    completion(.failure(error ?? CKError(.internalError)))
                }
            }
        }
    }

    private func resolveCurrentUserRecordName(completion: @escaping (Result<String, Error>) -> Void) {
        if let cached = defaults.string(forKey: Keys.currentUserRecordName), cached.isEmpty == false {
            completion(.success(cached))
            return
        }

        container.fetchUserRecordID { [weak self] recordID, error in
            if let recordID {
                Task { @MainActor in
                    self?.defaults.set(recordID.recordName, forKey: Keys.currentUserRecordName)
                }
                completion(.success(recordID.recordName))
            } else {
                completion(.failure(error ?? CKError(.notAuthenticated)))
            }
        }
    }

    private func cacheCurrentUserRecordID() {
        resolveCurrentUserRecordName { _ in }
    }

    private var currentDeviceRecordNameFallback: String {
        if let cached = defaults.string(forKey: Keys.currentUserRecordName), cached.isEmpty == false {
            return cached
        }

        let fallback = "device-\(UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString)"
        defaults.set(fallback, forKey: Keys.currentUserRecordName)
        return fallback
    }

    private func member(from record: CKRecord) -> FamilyMember? {
        guard let name = record["displayName"] as? String,
              let latitude = record["latitude"] as? Double,
              let longitude = record["longitude"] as? Double
        else {
            return nil
        }

        let updatedAt = record["updatedAt"] as? Date ?? Date()
        let arrivedAt = record["arrivedAt"] as? Date ?? updatedAt
        let address = record["address"] as? String

        return member(
            name: name,
            latitude: latitude,
            longitude: longitude,
            address: address,
            arrivedAt: arrivedAt,
            updatedAt: updatedAt
        )
    }

    private func member(
        name: String,
        latitude: Double,
        longitude: Double,
        address: String?,
        arrivedAt: Date,
        updatedAt: Date
    ) -> FamilyMember {
        FamilyMember(
            name: name,
            phoneNumber: nil,
            emailAddress: nil,
            device: "iPhone",
            status: .live,
            place: "Live shared location",
            address: address ?? Self.coordinateSummary(latitude: latitude, longitude: longitude),
            batteryLevel: 0,
            updatedAt: updatedAt.formatted(.relative(presentation: .named)),
            arrivedAt: arrivedAt,
            lastLocationUpdate: updatedAt,
            isLocationShared: true,
            tint: .green,
            latitude: latitude,
            longitude: longitude,
            speed: nil,
            eta: nil
        )
    }

    private func shouldPublish(_ location: CLLocation) -> Bool {
        guard location.horizontalAccuracy >= 0 else { return false }

        guard let lastPublishedLocation, let lastPublishedAt else {
            return true
        }

        let movedFarEnough = location.distance(from: lastPublishedLocation) >= 50
        let oldEnough = Date().timeIntervalSince(lastPublishedAt) >= 60
        return movedFarEnough || oldEnough
    }

    private func markPublished(_ location: CLLocation) {
        lastPublishedLocation = location
        lastPublishedAt = Date()
    }

    private nonisolated static func arrivalDate(for location: CLLocation, existingRecord: CKRecord?) -> Date {
        guard let existingRecord,
              let latitude = existingRecord["latitude"] as? Double,
              let longitude = existingRecord["longitude"] as? Double,
              let arrivedAt = existingRecord["arrivedAt"] as? Date
        else {
            return Date()
        }

        let previousLocation = CLLocation(latitude: latitude, longitude: longitude)
        let distance = location.distance(from: previousLocation)
        return distance < 100 ? arrivedAt : Date()
    }

    private nonisolated static func resolveAddress(for location: CLLocation, completion: @escaping (String) -> Void) {
        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            let placemark = placemarks?.first
            let components = [
                placemark?.subThoroughfare,
                placemark?.thoroughfare,
                placemark?.locality,
                placemark?.administrativeArea
            ]
            .compactMap { $0 }

            completion(components.isEmpty ? Self.coordinateSummary(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude) : components.joined(separator: ", "))
        }
    }

    private nonisolated static func coordinateSummary(latitude: Double, longitude: Double) -> String {
        "\(latitude.formatted(.number.precision(.fractionLength(5)))), \(longitude.formatted(.number.precision(.fractionLength(5))))"
    }
}

final class CloudSharingDelegate: NSObject, UICloudSharingControllerDelegate {
    static let shared = CloudSharingDelegate()

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
        "Whereabouts Family Circle"
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
                    address: Self.coordinateSummary(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                    arrivedAt: Date(),
                    updatedAt: Date()
                )
            )
            try saveLocalTestRecords(records, to: localTestTransportURL)
            markPublished(location)
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
                .filter { $0.circleCode == circleCode && $0.deviceID != currentDeviceRecordNameFallback }
                .map {
                    member(
                        name: $0.displayName,
                        latitude: $0.latitude,
                        longitude: $0.longitude,
                        address: $0.address,
                        arrivedAt: $0.arrivedAt,
                        updatedAt: $0.updatedAt
                    )
                }
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
}

private struct LocalSharedLocationRecord: Codable {
    var circleCode: String
    var deviceID: String
    var displayName: String
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var address: String
    var arrivedAt: Date
    var updatedAt: Date
}
#endif
