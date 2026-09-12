import CloudKit
import CoreLocation
import XCTest
@testable import FamilyLocator

@MainActor
final class InvitationTests: XCTestCase {
    private var directories: [URL] = []
    private var suites: [String] = []
    private let url = URL(string: "https://www.icloud.com/share/test-family-invitation")!

    override func tearDown() {
        for url in directories { try? FileManager.default.removeItem(at: url) }
        for name in suites { UserDefaults.standard.removePersistentDomain(forName: name) }
        super.tearDown()
    }
    private func defaults() -> UserDefaults {
        let name = "WhereaboutsInvitations-\(UUID())"
        suites.append(name)
        return UserDefaults(suiteName: name)!
    }
    private func disk() -> SharingPersistence {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        directories.append(folder)
        return SharingPersistence(url: folder.appending(path: "state.json"))
    }
    private func store(_ transport: InviteTransport, disk: SharingPersistence? = nil,
                       timeout: Duration = .seconds(3)) -> CloudLocationSharingStore {
        CloudLocationSharingStore(defaults: defaults(), transport: transport, persistence: disk ?? self.disk(),
                                  addressResolver: { _ in "Test address" }, invitationTimeout: timeout)
    }
    private func review(_ cloud: CloudLocationSharingStore) async {
        cloud.receiveInvitationLink(url.absoluteString)
        cloud.inspectPendingInvite()
        await cloud.waitForInvitationOperation()
    }
    private func join(_ cloud: CloudLocationSharingStore) async {
        cloud.acceptPendingInvite()
        await cloud.waitForInvitationOperation()
    }

    func testJoinPathRequiresConfirmationThenPublishesBothDirections() async throws {
        let server = InviteServer()
        let owner = store(InviteTransport(user: "alice", server: server))
        let transport = InviteTransport(server: server)
        let recipient = store(transport)
        let prepared = expectation(description: "Owner created private share")
        owner.prepareShare { result in
            if case .failure(let error) = result { XCTFail(error.localizedDescription) }
            prepared.fulfill()
        }
        await fulfillment(of: [prepared], timeout: 3)
        await review(recipient)
        XCTAssertEqual(recipient.invitationPhase, .ready)
        XCTAssertFalse(recipient.hasActiveCircle)
        XCTAssertEqual(transport.acceptCount, 0)
        await join(recipient)
        XCTAssertEqual(recipient.invitationPhase, .joined)
        XCTAssertTrue(recipient.isCircleVerified)
        XCTAssertTrue(server.accepted.contains("bob"))
        XCTAssertFalse(recipient.hasPendingInvite)
        let fix = CLLocation(coordinate: .init(latitude: 47, longitude: -122), altitude: 0,
                             horizontalAccuracy: 10, verticalAccuracy: -1, timestamp: Date())
        recipient.publish(location: fix, displayName: "Bob")
        XCTAssertFalse(recipient.hasPendingUpload, "Joining must not enable sharing")
        owner.setPublishingAllowed(true)
        recipient.setPublishingAllowed(true)
        owner.publish(location: fix, displayName: "Alice")
        recipient.publish(location: fix, displayName: "Bob")
        await owner.syncNow()
        await recipient.syncNow()
        _ = await owner.refresh()
        _ = await recipient.refresh()
        XCTAssertEqual(owner.remoteMembers.map(\.name), ["Bob"])
        XCTAssertEqual(recipient.remoteMembers.map(\.name), ["Alice"])
        XCTAssertNotNil(recipient.lastPublishedAt)
    }

    func testInvitationSurvivesRelaunchBeforeSignIn() async {
        let transport = InviteTransport()
        let persistence = disk()
        store(transport, disk: persistence).receiveInvitationLink(url.absoluteString)
        XCTAssertEqual(transport.resolveCount, 0)
        let restored = store(transport, disk: persistence)
        XCTAssertTrue(restored.hasPendingInvite)
        restored.inspectPendingInvite()
        await restored.waitForInvitationOperation()
        XCTAssertEqual(restored.invitationPhase, .ready)
        XCTAssertEqual(transport.acceptCount, 0)
    }

    func testDownloadLinkNeverMakesNetworkRequest() {
        let transport = InviteTransport()
        let cloud = store(transport)
        cloud.receiveInvitationLink("https://testflight.apple.com/join/dJhEQf75")
        cloud.inspectPendingInvite()
        XCTAssertEqual(cloud.invitationPhase, .failed)
        XCTAssertTrue(cloud.invitationMessage?.contains("installs Whereabouts") == true)
        XCTAssertFalse(cloud.hasPendingInvite)
        XCTAssertEqual(transport.resolveCount, 0)
    }

    func testEntryLinkKeepsPrivateInvitationOutOfRequestAndRoundTrips() throws {
        let entry = try InvitationLink.entryURL(for: url)
        XCTAssertEqual(entry.host, "lncrom.github.io")
        XCTAssertNil(entry.query)
        XCTAssertEqual(entry.path, "/whereabouts/join")
        XCTAssertNotNil(entry.fragment)
        XCTAssertEqual(try InvitationLink.parse(entry.absoluteString), url)
        XCTAssertEqual(try InvitationLink.parse("Join our circle: " + entry.absoluteString), url)
        XCTAssertThrowsError(try InvitationLink.entryURL(for: URL(string: "https://apps.apple.com/app/id123")!))
        XCTAssertThrowsError(try InvitationLink.parse(entry.absoluteString.replacingOccurrences(of: "https://lncrom", with: "http://lncrom")))
        XCTAssertThrowsError(try InvitationLink.parse(entry.absoluteString.replacingOccurrences(of: "lncrom.github.io", with: "lncrom.github.io.evil.test")))
    }

    func testNamedRecipientIsAddedBeforeLinkIsReturned() async throws {
        let transport = InviteTransport(user: "alice")
        let cloud = store(transport)
        let sent = expectation(description: "Private recipient invitation saved")
        cloud.prepareShare(recipient: .email("bob@example.com")) { result in
            switch result {
            case .success(let value):
                XCTAssertEqual(transport.invited, [.email("bob@example.com")])
                XCTAssertEqual(value.entryURL?.host, "lncrom.github.io")
                XCTAssertTrue(cloud.isCircleVerified)
            case .failure(let error): XCTFail(error.localizedDescription)
            }
            sent.fulfill()
        }
        await fulfillment(of: [sent], timeout: 3)
        XCTAssertFalse(transport.server.accepted.contains("bob"), "Inviting must not accept for the recipient")
    }

    func testFailedRecipientLookupNeverProducesDeliveryLink() async {
        let transport = InviteTransport(user: "alice")
        transport.inviteFailure = InvitationError.recipientNotFound
        let cloud = store(transport)
        let failed = expectation(description: "Recipient not found")
        cloud.prepareShare(recipient: .email("missing@example.com")) { result in
            if case .success = result { XCTFail("Do not offer an unapproved invitation for delivery") }
            failed.fulfill()
        }
        await fulfillment(of: [failed], timeout: 3)
        XCTAssertTrue(transport.invited.isEmpty)
    }

    func testRecipientValidationAcceptsAppleEmailAndInternationalPhone() throws {
        XCTAssertEqual(try InvitationRecipient(" bob@example.com "), .email("bob@example.com"))
        XCTAssertEqual(try InvitationRecipient("+1 (425) 555-0123"), .phone("+14255550123"))
        for value in ["", "@example.com", "bob@", "bob @example.com", "12345", "+1abc2345678", "bob@example.com@evil.test"] {
            XCTAssertThrowsError(try InvitationRecipient(value))
        }
    }

    func testInvalidReplacementCannotResumePreviousInvitation() async {
        let transport = InviteTransport()
        let cloud = store(transport)
        await review(cloud)
        cloud.receiveInvitationLink("https://testflight.apple.com/join/example")
        cloud.inspectPendingInvite()
        await join(cloud)
        XCTAssertEqual(cloud.invitationPhase, .failed)
        XCTAssertFalse(cloud.hasPendingInvite)
        XCTAssertNil(cloud.invitation)
        XCTAssertEqual(transport.acceptCount, 0)
    }

    func testRuntimeOpeningInvitationOnlyPreviewsIt() async {
        let transport = InviteTransport()
        let cloud = store(transport)
        let auth = AuthStore(defaults: defaults())
        auth.finishSignIn(name: "Bob", email: "", accountID: "bob")
        let runtime = SharingRuntime(auth: auth, location: LocationSharingStore(defaults: defaults()),
                                     cloud: cloud, monitorsEnabled: false)
        runtime.receiveInvitationURL(url)
        await cloud.waitForInvitationOperation()
        XCTAssertEqual(cloud.invitationPhase, .ready)
        XCTAssertEqual(transport.acceptCount, 0)
        XCTAssertFalse(runtime.location.isLiveSharingEnabled)
    }

    func testDismissedInvitationIgnoresLateMetadata() async throws {
        let transport = InviteTransport()
        transport.resolveDelay = .milliseconds(50)
        let cloud = store(transport)
        cloud.receiveInvitationLink(url.absoluteString)
        cloud.inspectPendingInvite()
        await Task.yield()
        cloud.cancelInvitation()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(cloud.invitationPhase, .idle)
        XCTAssertFalse(cloud.hasPendingInvite)
        XCTAssertNil(cloud.invitation)
    }

    func testSuccessfulJoinDoesNotTimeOutDuringLaterRefresh() async {
        let transport = InviteTransport()
        transport.refreshDelay = .milliseconds(80)
        let cloud = store(transport, timeout: .milliseconds(20))
        await review(cloud)
        await join(cloud)
        XCTAssertEqual(cloud.invitationPhase, .joined)
        XCTAssertTrue(cloud.isCircleVerified)
        XCTAssertFalse(cloud.hasPendingInvite)
    }

    func testSharePreparationTimeoutCompletesExactlyOnce() async throws {
        let transport = InviteTransport(user: "alice")
        transport.createDelay = .milliseconds(80)
        let cloud = store(transport, timeout: .milliseconds(20))
        var completions = 0
        cloud.prepareShare { result in
            completions += 1
            if case .success = result { XCTFail("Late preparation must not display a sharing sheet") }
        }
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(completions, 1)
        XCTAssertFalse(cloud.isPreparingShare)
        XCTAssertFalse(cloud.hasActiveCircle)
    }

    func testWrongAppAndReadOnlyInvitesRejectedBeforeAcceptance() async {
        for readOnly in [false, true] {
            let transport = InviteTransport()
            transport.wrongContainer = !readOnly
            transport.readOnly = readOnly
            let cloud = store(transport)
            await review(cloud)
            await join(cloud)
            XCTAssertEqual(cloud.invitationPhase, .failed)
            XCTAssertEqual(transport.acceptCount, 0)
            XCTAssertFalse(cloud.hasActiveCircle)
        }
    }

    func testOwnerOpeningOwnInvitationGetsExplanation() async {
        let transport = InviteTransport(user: "alice")
        let cloud = store(transport)
        await review(cloud)
        await join(cloud)
        XCTAssertEqual(cloud.invitationPhase, .ownInvite)
        XCTAssertEqual(transport.acceptCount, 0)
    }

    func testAcceptWithoutSharedZoneDoesNotClaimSuccessAndCanRetry() async {
        let transport = InviteTransport()
        transport.exposeAcceptedZone = false
        let cloud = store(transport)
        await review(cloud)
        await join(cloud)
        XCTAssertEqual(cloud.invitationPhase, .failed)
        XCTAssertFalse(cloud.hasActiveCircle)
        XCTAssertTrue(cloud.hasPendingInvite)
        transport.exposeAcceptedZone = true
        cloud.inspectPendingInvite()
        await cloud.waitForInvitationOperation()
        await join(cloud)
        XCTAssertEqual(cloud.invitationPhase, .joined)
    }

    func testUnreadableRecordsDoNotActivateCircle() async {
        let transport = InviteTransport()
        transport.readFailure = CKError(.networkUnavailable)
        let cloud = store(transport)
        await review(cloud)
        await join(cloud)
        XCTAssertEqual(cloud.invitationPhase, .failed)
        XCTAssertFalse(cloud.isCircleVerified)
        XCTAssertFalse(cloud.hasActiveCircle)
    }

    func testOfflineInvitationRetriesWithoutLosingLink() async {
        let transport = InviteTransport()
        transport.resolveFailure = CKError(.networkUnavailable)
        let cloud = store(transport)
        await review(cloud)
        XCTAssertEqual(cloud.invitationPhase, .failed)
        XCTAssertTrue(cloud.hasPendingInvite)
        transport.resolveFailure = nil
        cloud.inspectPendingInvite()
        await cloud.waitForInvitationOperation()
        XCTAssertEqual(cloud.invitationPhase, .ready)
    }

    func testWrongICloudAccountCannotJoin() async {
        let cloud = store(InviteTransport(user: "uninvited"))
        await review(cloud)
        XCTAssertEqual(cloud.invitationPhase, .failed)
        XCTAssertTrue(cloud.invitationMessage?.contains("not invited") == true)
        XCTAssertFalse(cloud.hasActiveCircle)
    }

    func testTimeoutReleasesUIAndIgnoresLateResponse() async throws {
        let transport = InviteTransport()
        transport.resolveDelay = .milliseconds(100)
        let cloud = store(transport, timeout: .milliseconds(10))
        await review(cloud)
        try await Task.sleep(for: .milliseconds(120))
        XCTAssertEqual(cloud.invitationPhase, .failed)
        XCTAssertFalse(cloud.hasActiveCircle)
        XCTAssertTrue(cloud.hasPendingInvite)
        transport.resolveDelay = .zero
        cloud.inspectPendingInvite()
        await cloud.waitForInvitationOperation()
        XCTAssertEqual(cloud.invitationPhase, .ready)
    }

    func testDuplicateLinkDoesNotResolveOrAcceptTwice() async {
        let transport = InviteTransport()
        let cloud = store(transport)
        cloud.receiveInvitationLink(url.absoluteString)
        cloud.inspectPendingInvite()
        cloud.receiveInvitationLink(url.absoluteString)
        cloud.inspectPendingInvite()
        await cloud.waitForInvitationOperation()
        XCTAssertEqual(transport.resolveCount, 1)
        XCTAssertEqual(transport.acceptCount, 0)
    }

    func testAccountChangeDuringAcceptCannotActivateOldInvitation() async {
        let transport = InviteTransport()
        let cloud = store(transport)
        await review(cloud)
        transport.beforeAccept = { transport.user = "different-account"; cloud.accountDidChange() }
        await join(cloud)
        XCTAssertFalse(cloud.hasActiveCircle)
        XCTAssertFalse(cloud.isCircleVerified)
    }

    func testSwitchCirclePausesPreviouslyEnabledSharing() async throws {
        let transport = InviteTransport()
        let cloud = store(transport)
        try await cloud.verifyAccount()
        cloud.activate(.init(zoneName: "WhereaboutsFamilyCircle", ownerName: CKCurrentUserDefaultName, isOwner: true))
        let auth = AuthStore(defaults: defaults())
        auth.finishSignIn(name: "Bob", email: "", accountID: "bob")
        let location = LocationSharingStore(defaults: defaults())
        location.isLiveSharingEnabled = true
        let runtime = SharingRuntime(auth: auth, location: location, cloud: cloud, monitorsEnabled: false)
        await review(cloud)
        XCTAssertTrue(cloud.invitationChangesCircle)
        await join(cloud)
        XCTAssertEqual(cloud.invitationPhase, .joined)
        XCTAssertFalse(runtime.location.isLiveSharingEnabled)
    }

    func testLinkParserSupportsMessagesAndRejectsSpoofedHosts() throws {
        XCTAssertEqual(try InvitationLink.parse("Join my family: \(url.absoluteString)"), url)
        var wrapper = URLComponents(string: "whereabouts://join")!
        wrapper.queryItems = [.init(name: "invite", value: url.absoluteString)]
        XCTAssertEqual(try InvitationLink.parse(wrapper.string!), url)
        for value in ["https://icloud.com.evil.test/share/abc", "http://icloud.com/share/abc",
                      "https://icloud.com@evil.test/share/abc", "https://www.icloud.com/photos/abc",
                      "whereabouts://join", "https://www.icloud.com/share/", "https://www.icloud.com:8443/share/abc"] {
            XCTAssertThrowsError(try InvitationLink.parse(value), value)
        }
    }
}

@MainActor private final class InviteServer {
    var accepted: Set<String> = []
    var records: [String: CKRecord] = [:]
}

@MainActor private final class InviteTransport: LocationCloudTransport {
    var user: String
    let server: InviteServer
    let sharedScope = CircleScope(zoneName: "WhereaboutsFamilyCircle", ownerName: "alice", isOwner: false)
    var acceptCount = 0
    var resolveCount = 0
    var wrongContainer = false
    var readOnly = false
    var exposeAcceptedZone = true
    var resolveFailure: Error?
    var readFailure: Error?
    var resolveDelay: Duration = .zero
    var refreshDelay: Duration = .zero
    var createDelay: Duration = .zero
    private var readCount = 0
    var beforeAccept: (() -> Void)?
    var invited: [InvitationRecipient] = []
    var inviteFailure: Error?
    init(user: String = "bob", server: InviteServer? = nil) { self.user = user; self.server = server ?? InviteServer() }
    func accountID() async throws -> String { user }
    func invitation(for url: URL) async throws -> CircleInvitation {
        resolveCount += 1
        if resolveDelay != .zero { try? await Task.sleep(for: resolveDelay) }
        if let resolveFailure { throw resolveFailure }
        guard ["alice", "bob"].contains(user) else { throw CKError(.permissionFailure) }
        return CircleInvitation(url: url, containerID: wrongContainer ? "iCloud.other.app" : CloudKitTransport.containerID,
                                scope: sharedScope, ownerID: "alice", ownerName: "Alice", isOwner: user == "alice",
                                isAccepted: server.accepted.contains(user), canWrite: !readOnly)
    }
    func accept(_ invitation: CircleInvitation) async throws {
        acceptCount += 1
        let acceptingUser = user
        beforeAccept?()
        server.accepted.insert(acceptingUser)
    }
    func invite(_ recipient: InvitationRecipient, to share: CKShare, in scope: CircleScope) async throws -> URL {
        if let inviteFailure { throw inviteFailure }
        XCTAssertTrue(scope.isOwner)
        XCTAssertEqual(share.publicPermission, .none)
        invited.append(recipient)
        return URL(string: "https://www.icloud.com/share/test-family-invitation")!
    }
    func zones(shared: Bool) async throws -> [CKRecordZone] {
        if shared && exposeAcceptedZone && server.accepted.contains(user) { return [CKRecordZone(zoneID: sharedScope.zoneID)] }
        return []
    }
    func createZone(_ scope: CircleScope) async throws {
        if createDelay != .zero { try? await Task.sleep(for: createDelay) }
    }
    func record(_ id: CKRecord.ID, in scope: CircleScope) async throws -> CKRecord {
        guard let record = server.records[id.recordName] else { throw CKError(.unknownItem) }
        return record
    }
    func save(_ record: CKRecord, in scope: CircleScope) async throws -> CKRecord {
        server.records[record.recordID.recordName] = record
        return record
    }
    func records(in scope: CircleScope) async throws -> [CKRecord] {
        readCount += 1
        if readCount > 1 && refreshDelay != .zero { try? await Task.sleep(for: refreshDelay) }
        if let readFailure { throw readFailure }
        if !scope.isOwner && !server.accepted.contains(user) { throw CKError(.permissionFailure) }
        return Array(server.records.values)
    }
    func delete(_ id: CKRecord.ID, in scope: CircleScope) async throws { server.records.removeValue(forKey: id.recordName) }
    func leave(_ scope: CircleScope) async throws { server.accepted.remove(user) }
    func subscribe(shared: Bool) async throws {}
}
