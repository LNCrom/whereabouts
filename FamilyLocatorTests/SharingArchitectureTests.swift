import CloudKit
import CoreLocation
import XCTest
@testable import FamilyLocator

@MainActor
final class SharingArchitectureTests: XCTestCase {
    private var directories: [URL] = []
    private var suites: [String] = []

    override func tearDown() {
        for directory in directories { try? FileManager.default.removeItem(at: directory) }
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        super.tearDown()
    }

    private func defaults() -> UserDefaults {
        let name = "WhereaboutsArchitecture-\(UUID())"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func persistence() -> SharingPersistence {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        directories.append(directory)
        return SharingPersistence(url: directory.appending(path: "state.json"))
    }

    private func store(_ transport: FakeCloud, persistence: SharingPersistence? = nil) -> CloudLocationSharingStore {
        CloudLocationSharingStore(defaults: defaults(), transport: transport,
            persistence: persistence ?? self.persistence(), addressResolver: { _ in "Test address" })
    }

    private func location(_ offset: Double = 0, date: Date = Date()) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 47 + offset, longitude: -122),
                   altitude: 0, horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: date)
    }

    private let ownerScope = CircleScope(zoneName: "WhereaboutsFamilyCircle", ownerName: CKCurrentUserDefaultName, isOwner: true)
    private let joinedScope = CircleScope(zoneName: "WhereaboutsFamilyCircle", ownerName: "alice", isOwner: false)

    func testTwoAuthorizedPersonasPublishAndSeeEachOtherInOneCircle() async throws {
        let server = FakeServer()
        let alice = store(FakeCloud(user: "alice", server: server))
        let bob = store(FakeCloud(user: "bob", server: server))
        try await alice.verifyAccount()
        try await bob.verifyAccount()
        alice.activate(ownerScope)
        bob.activate(joinedScope)
        alice.setPublishingAllowed(true)
        bob.setPublishingAllowed(true)
        alice.publish(location: location(), displayName: "Alice")
        bob.publish(location: location(0.01), displayName: "Bob")
        await alice.syncNow()
        await bob.syncNow()
        _ = await alice.refresh()
        _ = await bob.refresh()
        XCTAssertEqual(alice.remoteMembers.map(\.name), ["Bob"])
        XCTAssertEqual(bob.remoteMembers.map(\.name), ["Alice"])
        let identity = alice.remoteMembers.first?.id
        _ = await alice.refresh()
        XCTAssertEqual(alice.remoteMembers.first?.id, identity)
    }

    func testOfflineUploadSurvivesRelaunchAndRetriesWithOriginalTimestamp() async throws {
        let transport = FakeCloud()
        let disk = persistence()
        let original = store(transport, persistence: disk)
        try await original.verifyAccount()
        original.activate(ownerScope)
        original.setPublishingAllowed(true)
        transport.failure = CKError(.networkUnavailable)
        let fix = location(date: Date().addingTimeInterval(-30))
        original.publish(location: fix, displayName: "Alice")
        await original.syncNow()
        XCTAssertTrue(original.hasPendingUpload)
        let recovered = store(transport, persistence: disk)
        transport.failure = nil
        try await recovered.verifyAccount()
        recovered.setPublishingAllowed(true)
        await recovered.syncNow()
        XCTAssertFalse(recovered.hasPendingUpload)
        XCTAssertEqual(transport.server.records.values.first?["updatedAt"] as? Date, fix.timestamp)
        original.setPublishingAllowed(false)
    }

    func testPauseDuringSaveDeletesInFlightLocation() async throws {
        let transport = FakeCloud()
        let cloud = store(transport)
        try await cloud.verifyAccount()
        cloud.activate(ownerScope)
        cloud.setPublishingAllowed(true)
        transport.beforeSave = { cloud.removePublishedLocation() }
        cloud.publish(location: location(), displayName: "Alice")
        await cloud.syncNow()
        XCTAssertTrue(transport.server.records.isEmpty)
        XCTAssertFalse(cloud.hasPendingUpload)
    }

    func testAccountSwitchClearsOldCircleAndDoesNotPublishAsPreviousUser() async throws {
        let transport = FakeCloud()
        let cloud = store(transport)
        try await cloud.verifyAccount()
        cloud.activate(ownerScope)
        transport.user = "bob"
        try await cloud.verifyAccount(force: true)
        cloud.publish(location: location(), displayName: "Alice")
        XCTAssertFalse(cloud.hasActiveCircle)
        XCTAssertNotNil(cloud.accountChangedID)
        XCTAssertFalse(cloud.hasPendingUpload)
    }

    func testJoinedScopeMigratesAheadOfAccidentallyCreatedOwnerCircle() {
        let settings = defaults()
        settings.set("WhereaboutsFamilyCircle", forKey: "whereabouts.cloud.privateZoneName")
        settings.set("WhereaboutsFamilyCircle", forKey: "whereabouts.cloud.sharedZoneName")
        settings.set("alice", forKey: "whereabouts.cloud.sharedZoneOwnerName")
        let cloud = CloudLocationSharingStore(defaults: settings, transport: FakeCloud(), persistence: persistence())
        XCTAssertTrue(cloud.hasActiveCircle)
        XCTAssertFalse(cloud.isCircleOwner)
    }

    func testOldSamplesAreNotUploadedAndOldRecordsAreNotLive() async throws {
        let transport = FakeCloud()
        let cloud = store(transport)
        try await cloud.verifyAccount()
        cloud.activate(ownerScope)
        cloud.setPublishingAllowed(true)
        cloud.publish(location: location(date: Date().addingTimeInterval(-600)))
        XCTAssertFalse(cloud.hasPendingUpload)
        let record = CKRecord(recordType: "WhereaboutsLocation")
        record["displayName"] = "Bob" as CKRecordValue
        record["latitude"] = 47.0 as CKRecordValue
        record["longitude"] = -122.0 as CKRecordValue
        record["updatedAt"] = Date().addingTimeInterval(-600) as CKRecordValue
        let member = CloudLocationSharingStore.member(from: record)
        XCTAssertEqual(member?.status, .offline)
        XCTAssertEqual(member?.place, "Last known location")
        XCTAssertEqual(member?.batteryLevel, -1)
    }

    func testApproximateSharingActuallyReducesCoordinatePrecision() {
        let precise = location(0.0012345)
        let approximate = LocationSample(precise, precise: false)
        XCTAssertEqual(approximate.latitude, 47.0)
        XCTAssertGreaterThanOrEqual(approximate.accuracy, 1500)
        XCTAssertNotEqual(approximate.latitude, precise.coordinate.latitude)
    }

    func testArrivalUsesFixedAnchorSoSlowMovementDoesNotAccumulateForever() {
        let now = Date()
        var arrival = ArrivalState(anchor: LocationSample(location(date: now)), arrivedAt: now)
        arrival.observe(LocationSample(location(0.0005, date: now.addingTimeInterval(60))))
        XCTAssertEqual(arrival.arrivedAt, now)
        arrival.observe(LocationSample(location(0.0011, date: now.addingTimeInterval(120))))
        XCTAssertEqual(arrival.arrivedAt, now.addingTimeInterval(120))
    }

    func testScreenLockDoesNotReplaceLocationOrCloudServices() {
        let auth = AuthStore(defaults: defaults())
        auth.finishSignIn(name: "Alice", email: "", accountID: "alice")
        let locationStore = LocationSharingStore(defaults: defaults())
        locationStore.isLiveSharingEnabled = true
        let cloud = store(FakeCloud())
        let runtime = SharingRuntime(auth: auth, location: locationStore, cloud: cloud, monitorsEnabled: false)
        runtime.phaseChanged(.background)
        XCTAssertFalse(auth.isUnlocked)
        XCTAssertTrue(auth.isSignedIn)
        XCTAssertTrue(runtime.location === locationStore)
        XCTAssertTrue(runtime.cloud === cloud)
        XCTAssertTrue(locationStore.isLiveSharingEnabled)
    }

    func testNewInstallRequiresExplicitSharingConsent() {
        XCTAssertFalse(LocationSharingStore(defaults: defaults()).isLiveSharingEnabled)
    }

    func testOfflinePausePersistsRemovalAndClearsUpload() async throws {
        let transport = FakeCloud()
        let disk = persistence()
        let cloud = store(transport, persistence: disk)
        try await cloud.verifyAccount()
        cloud.activate(ownerScope)
        cloud.setPublishingAllowed(true)
        cloud.publish(location: location())
        await cloud.syncNow()
        XCTAssertEqual(transport.server.records.count, 1)
        transport.failure = CKError(.networkUnavailable)
        cloud.removePublishedLocation()
        await cloud.syncNow()
        XCTAssertFalse(cloud.hasPendingUpload)
        XCTAssertEqual(try disk.load().removals.count, 1)
        transport.failure = nil
        let recovered = store(transport, persistence: disk)
        try await recovered.verifyAccount()
        await recovered.syncNow()
        XCTAssertTrue(transport.server.records.isEmpty)
        XCTAssertTrue(try disk.load().removals.isEmpty)
    }

    func testSwitchingCircleDiscardsPendingFixForOldCircle() async throws {
        let transport = FakeCloud(user: "bob")
        let cloud = store(transport)
        try await cloud.verifyAccount()
        cloud.activate(ownerScope)
        cloud.setPublishingAllowed(true)
        cloud.publish(location: location())
        cloud.activate(joinedScope)
        await cloud.syncNow()
        XCTAssertTrue(transport.server.records.isEmpty)
        cloud.setPublishingAllowed(true)
        cloud.publish(location: location(0.01))
        await cloud.syncNow()
        XCTAssertEqual(transport.server.records.count, 1)
        XCTAssertTrue(transport.server.records.keys.allSatisfy { $0.hasPrefix("alice/") })
    }

    func testLegacyProfileBindingPreservesScreenLock() {
        let settings = defaults()
        UserProfile(id: UUID().uuidString, name: "Alice", email: "alice@example.test").save(to: settings)
        let auth = AuthStore(defaults: settings)
        auth.bindLegacyProfile(to: "alice")
        XCTAssertEqual(auth.profile?.id, "alice")
        XCTAssertFalse(auth.isUnlocked)
    }

    func testQueuedFixCannotUploadAfterSharingDeadline() async throws {
        let transport = FakeCloud()
        let cloud = store(transport)
        try await cloud.verifyAccount()
        cloud.activate(ownerScope)
        cloud.setPublishingAllowed(true, expiresAt: Date().addingTimeInterval(-1))
        cloud.publish(location: location())
        await cloud.syncNow()
        XCTAssertTrue(transport.server.records.isEmpty)
        XCTAssertFalse(cloud.hasPendingUpload)
    }

    func testLeaveRemovesMembershipOnServer() async throws {
        let transport = FakeCloud(user: "bob")
        let cloud = store(transport)
        try await cloud.verifyAccount()
        cloud.activate(joinedScope)
        let completion = expectation(description: "Left circle")
        cloud.leaveCircle { completion.fulfill() }
        await fulfillment(of: [completion], timeout: 3)
        XCTAssertEqual(transport.left, [joinedScope])
        XCTAssertFalse(cloud.hasActiveCircle)
    }
}

@MainActor
private final class FakeServer {
    var records: [String: CKRecord] = [:]
}

@MainActor
private final class FakeCloud: LocationCloudTransport {
    var user: String
    let server: FakeServer
    var failure: Error?
    var beforeSave: (() -> Void)?
    var left: [CircleScope] = []

    init(user: String = "alice", server: FakeServer? = nil) { self.user = user; self.server = server ?? FakeServer() }
    private func check() throws { if let failure { throw failure } }
    private func prefix(_ scope: CircleScope) -> String { (scope.isOwner ? user : scope.ownerName) + "/" + scope.zoneName + "/" }
    func accountID() async throws -> String { try check(); return user }
    func zones(shared: Bool) async throws -> [CKRecordZone] { try check(); return [] }
    func createZone(_ scope: CircleScope) async throws { try check() }
    func record(_ id: CKRecord.ID, in scope: CircleScope) async throws -> CKRecord {
        try check()
        guard let record = server.records[prefix(scope) + id.recordName] else { throw CKError(.unknownItem) }
        return record
    }
    func save(_ record: CKRecord, in scope: CircleScope) async throws -> CKRecord {
        try check()
        beforeSave?()
        server.records[prefix(scope) + record.recordID.recordName] = record
        return record
    }
    func records(in scope: CircleScope) async throws -> [CKRecord] {
        try check()
        return server.records.filter { $0.key.hasPrefix(prefix(scope)) }.map(\.value)
    }
    func delete(_ id: CKRecord.ID, in scope: CircleScope) async throws { try check(); server.records.removeValue(forKey: prefix(scope) + id.recordName) }
    func leave(_ scope: CircleScope) async throws { try check(); left.append(scope) }
    func invitation(for url: URL) async throws -> CircleInvitation { throw CKError(.unknownItem) }
    func accept(_ invitation: CircleInvitation) async throws { try check() }
    func invite(_ recipient: InvitationRecipient, to share: CKShare, in scope: CircleScope) async throws -> URL { throw CKError(.unknownItem) }
    func subscribe(shared: Bool) async throws { try check() }
}
