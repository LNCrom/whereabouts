import CloudKit

struct CircleScope: Codable, Equatable {
    var zoneName: String
    var ownerName: String
    var isOwner: Bool

    var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName) }
}

@MainActor
protocol LocationCloudTransport {
    func accountID() async throws -> String
    func zones(shared: Bool) async throws -> [CKRecordZone]
    func createZone(_ scope: CircleScope) async throws
    func record(_ id: CKRecord.ID, in scope: CircleScope) async throws -> CKRecord
    func save(_ record: CKRecord, in scope: CircleScope) async throws -> CKRecord
    func records(in scope: CircleScope) async throws -> [CKRecord]
    func delete(_ id: CKRecord.ID, in scope: CircleScope) async throws
    func leave(_ scope: CircleScope) async throws
    func metadata(for url: URL) async throws -> CKShare.Metadata
    func accept(_ metadata: CKShare.Metadata) async throws
    func subscribe(shared: Bool) async throws
}

@MainActor
final class CloudKitTransport: LocationCloudTransport {
    static let containerID = "iCloud.com.lancecromwell.Whereabouts"
    let container = CKContainer(identifier: containerID)

    private func database(_ scope: CircleScope) -> CKDatabase {
        scope.isOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
    }

    func accountID() async throws -> String {
        guard try await container.accountStatus() == .available else { throw CKError(.notAuthenticated) }
        return try await container.userRecordID().recordName
    }

    func zones(shared: Bool) async throws -> [CKRecordZone] {
        try await (shared ? container.sharedCloudDatabase : container.privateCloudDatabase).allRecordZones()
    }

    func createZone(_ scope: CircleScope) async throws {
        _ = try await database(scope).save(CKRecordZone(zoneID: scope.zoneID))
    }

    func record(_ id: CKRecord.ID, in scope: CircleScope) async throws -> CKRecord {
        try await database(scope).record(for: id)
    }

    func save(_ record: CKRecord, in scope: CircleScope) async throws -> CKRecord {
        try await database(scope).save(record)
    }

    func records(in scope: CircleScope) async throws -> [CKRecord] {
        var records: [CKRecord.ID: CKRecord] = [:]
        var token: CKServerChangeToken?
        // Apply deletions across every page before publishing a consistent snapshot.
        while true {
            let page = try await database(scope).recordZoneChanges(inZoneWith: scope.zoneID, since: token)
            for (id, result) in page.modificationResultsByID { records[id] = try result.get().record }
            for deletion in page.deletions { records.removeValue(forKey: deletion.recordID) }
            token = page.changeToken
            if !page.moreComing { return Array(records.values) }
        }
    }

    func delete(_ id: CKRecord.ID, in scope: CircleScope) async throws {
        do { _ = try await database(scope).deleteRecord(withID: id) }
        catch let error as CKError where [.unknownItem, .zoneNotFound, .userDeletedZone].contains(error.code) { }
    }

    func leave(_ scope: CircleScope) async throws {
        // Deleting a shared-database zone removes this participant's access only.
        do { _ = try await database(scope).deleteRecordZone(withID: scope.zoneID) }
        catch let error as CKError where [.zoneNotFound, .userDeletedZone].contains(error.code) { }
    }

    func metadata(for url: URL) async throws -> CKShare.Metadata {
        try await container.shareMetadata(for: url)
    }

    func accept(_ metadata: CKShare.Metadata) async throws {
        let results = try await container.accept([metadata])
        guard let result = results[metadata] else { throw CKError(.internalError) }
        _ = try result.get()
    }

    func subscribe(shared: Bool) async throws {
        let database = shared ? container.sharedCloudDatabase : container.privateCloudDatabase
        let subscription = CKDatabaseSubscription(subscriptionID: shared ? "whereabouts-shared-v1" : "whereabouts-private-v1")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.save(subscription)
    }
}
