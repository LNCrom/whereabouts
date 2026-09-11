import CloudKit
import CoreLocation
import Foundation
import UIKit

@MainActor
final class CloudLocationSharingStore: ObservableObject {
    @Published private(set) var remoteMembers: [FamilyMember] = []
    @Published private(set) var statusMessage = "Connect to iCloud to start sharing."
    @Published private(set) var isFetching = false
    @Published private(set) var isPreparingShare = false
    @Published private(set) var inviteEventID: UUID?
    @Published private(set) var accountID: String?
    @Published private(set) var accountChangedID: UUID?
    @Published private(set) var circleRevision = 0
    @Published private(set) var invitationMessage: String?
    @Published private(set) var participants: [CircleParticipant] = []
    @Published private(set) var lastPublishedAt: Date?
    @Published private(set) var pushStatus = "Waiting for iCloud"

    private let transport: any LocationCloudTransport
    private let persistence: SharingPersistence
    private var state: SharingState
    private var publishingAllowed = false
    private var publishingExpiresAt: Date?
    private var syncTask: Task<Void, Never>?
    private var inviteTask: Task<Void, Never>?
    private var lastPublishedLocation: CLLocation?
    private var retryAttempt = 0
    private var retryTask: Task<Void, Never>?
    private var sessionGeneration = UUID()
    private var pendingMetadata: CKShare.Metadata?
    private var storageError: Error?
    private var verifiedAt: Date?
    private var subscribedAccount: String?
    private let addressResolver: (CLLocation) async -> String

    init(defaults: UserDefaults = .standard, transport: (any LocationCloudTransport)? = nil,
         persistence: SharingPersistence = .standard, addressResolver: ((CLLocation) async -> String)? = nil) {
        self.transport = transport ?? CloudKitTransport()
        self.persistence = persistence
        self.addressResolver = addressResolver ?? Self.resolveAddress
        do { state = try persistence.load() }
        catch { state = SharingState(); storageError = error }
        // Migrate existing installs without creating a second family circle.
        if state.scope == nil {
            if let name = defaults.string(forKey: "whereabouts.cloud.sharedZoneName"),
               let owner = defaults.string(forKey: "whereabouts.cloud.sharedZoneOwnerName") {
                state.scope = CircleScope(zoneName: name, ownerName: owner, isOwner: false)
            } else if let name = defaults.string(forKey: "whereabouts.cloud.privateZoneName") {
                state.scope = CircleScope(zoneName: name, ownerName: CKCurrentUserDefaultName, isOwner: true)
            }
            if state.accountID == nil { state.accountID = defaults.string(forKey: "whereabouts.cloud.currentUserRecordName") }
            if storageError == nil, (try? persistence.save(state)) != nil {
                for key in ["privateZoneName", "sharedZoneName", "sharedZoneOwnerName", "currentUserRecordName"] {
                    defaults.removeObject(forKey: "whereabouts.cloud." + key)
                }
            }
        }
    }

    var hasActiveCircle: Bool { state.scope != nil }
    var isCircleOwner: Bool { state.scope?.isOwner == true }
    var sharingTitle: String { isCircleOwner ? "Invite or manage family" : "Create family circle" }
    var hasPendingInvite: Bool { state.pendingInvite != nil || pendingMetadata != nil }
    var hasPendingUpload: Bool { state.pendingLocation != nil }

    func updateAccountStatus() { Task { _ = await refresh() } }

    @discardableResult
    func verifyAccount(force: Bool = false) async throws -> String {
        if !force, let accountID, let verifiedAt, Date().timeIntervalSince(verifiedAt) < 60 { return accountID }
        let generation = sessionGeneration
        let id = try await transport.accountID()
        guard generation == sessionGeneration else { throw CancellationError() }
        if let previous = state.accountID, previous != id {
            state = SharingState()
            publishingAllowed = false
            remoteMembers = []
            participants = []
            lastPublishedAt = nil
            lastPublishedLocation = nil
            accountChangedID = UUID()
            circleRevision += 1
        }
        state.accountID = id
        accountID = id
        verifiedAt = Date()
        try persist()
        return id
    }

    func accountDidChange() {
        sessionGeneration = UUID()
        verifiedAt = nil
        accountID = nil
        publishingAllowed = false
        remoteMembers = []
        participants = []
        subscribedAccount = nil
        retryTask?.cancel()
        accountChangedID = UUID()
        updateAccountStatus()
    }

    func setPublishingAllowed(_ allowed: Bool, discardPending: Bool = true, expiresAt: Date? = nil) {
        publishingAllowed = allowed
        publishingExpiresAt = expiresAt
        if !allowed, discardPending, state.pendingLocation != nil {
            state.pendingLocation = nil
            saveOrReport()
        }
    }

    func publish(location: CLLocation, displayName: String? = nil) {
        let sample = LocationSample(location)
        guard publishingAllowed, sample.isUsable(at: Date()), let scope = state.scope,
              let accountID, accountID == state.accountID else { return }
        if let lastPublishedLocation, let lastPublishedAt,
           location.distance(from: lastPublishedLocation) < 50,
           Date().timeIntervalSince(lastPublishedAt) < 60 { return }
        if state.arrival == nil { state.arrival = ArrivalState(anchor: sample, arrivedAt: sample.timestamp) }
        else { state.arrival?.observe(sample) }
        state.pendingLocation = PendingLocation(scope: scope, accountID: accountID,
            displayName: displayName ?? "Family member", sample: sample, arrivedAt: state.arrival!.arrivedAt,
            expiresAt: publishingExpiresAt)
        guard saveOrReport() else { return }
        startSync()
    }

    func fetchSharedLocations() { Task { _ = await refresh() } }

    @discardableResult
    func refresh() async -> Bool {
        updateFreshness()
        guard !isFetching else { return false }
        isFetching = true
        defer { isFetching = false }
        do {
            let id = try await verifyAccount()
            if subscribedAccount != id {
                do {
                    try await transport.subscribe(shared: false)
                    try await transport.subscribe(shared: true)
                    subscribedAccount = id
                    pushStatus = "Connected"
                } catch { pushStatus = "Unavailable; refresh remains active" }
            }
            try await restoreCircleIfNeeded()
            guard let scope = state.scope else {
                statusMessage = "iCloud connected. Create a circle or open your invitation."
                return false
            }
            let records = try await transport.records(in: scope)
            guard state.scope == scope, accountID == id else { return false }
            remoteMembers = records.filter { $0.recordType == "WhereaboutsLocation" && ($0["userRecordName"] as? String) != id }
                .compactMap(Self.member).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            await refreshParticipants(in: scope)
            statusMessage = state.pendingLocation == nil ? "Family locations updated." : "Location waiting to sync."
            startSync()
            return true
        } catch {
            handle(error)
            return false
        }
    }

    private func restoreCircleIfNeeded() async throws {
        guard state.scope == nil, state.restoreAllowed != false else { return }
        let shared = try await transport.zones(shared: true).filter { $0.zoneID.zoneName == "WhereaboutsFamilyCircle" }
        if shared.count == 1, let zone = shared.first {
            activate(CircleScope(zoneName: zone.zoneID.zoneName, ownerName: zone.zoneID.ownerName, isOwner: false))
        } else if shared.count > 1 {
            invitationMessage = "Several family circles were found. Open the invitation for the circle you want."
        } else {
            let owned = try await transport.zones(shared: false)
            if let zone = owned.first(where: { $0.zoneID.zoneName == "WhereaboutsFamilyCircle" }) {
                activate(CircleScope(zoneName: zone.zoneID.zoneName, ownerName: zone.zoneID.ownerName, isOwner: true))
            }
        }
    }

    func prepareShare(completion: @escaping (Result<(share: CKShare, container: CKContainer), Error>) -> Void) {
        guard !isPreparingShare else { return }
        guard !(hasActiveCircle && !isCircleOwner) else {
            completion(.failure(SharingError.alreadyJoined)); return
        }
        isPreparingShare = true
        Task {
            defer { isPreparingShare = false }
            do {
                _ = try await verifyAccount(force: true)
                try await restoreCircleIfNeeded()
                guard !(hasActiveCircle && !isCircleOwner) else { throw SharingError.alreadyJoined }
                let scope = state.scope ?? CircleScope(zoneName: "WhereaboutsFamilyCircle", ownerName: CKCurrentUserDefaultName, isOwner: true)
                try await transport.createZone(scope)
                let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: scope.zoneID)
                let share: CKShare
                do {
                    guard let existing = try await transport.record(id, in: scope) as? CKShare else { throw CKError(.internalError) }
                    share = existing
                } catch let error as CKError where error.code == .unknownItem {
                    share = CKShare(recordZoneID: scope.zoneID)
                    share[CKShare.SystemFieldKey.title] = "Whereabouts Family Circle" as CKRecordValue
                }
                share.publicPermission = .none
                guard let saved = try await transport.save(share, in: scope) as? CKShare else { throw CKError(.internalError) }
                activate(scope)
                invitationMessage = nil
                statusMessage = "Choose who to invite."
                completion(.success((saved, (transport as? CloudKitTransport)?.container ?? CKContainer(identifier: CloudKitTransport.containerID))))
            } catch { handle(error); completion(.failure(error)) }
        }
    }

    func receiveInvite(_ metadata: CKShare.Metadata) {
        guard metadata.containerIdentifier == CloudKitTransport.containerID else {
            invitationMessage = "This invitation belongs to another app."; return
        }
        pendingMetadata = metadata
        state.pendingInvite = metadata.share.url
        invitationMessage = "Invitation received. Unlock Whereabouts to join."
        saveOrReport()
        inviteEventID = UUID()
    }

    func acceptPendingInvite() {
        guard inviteTask == nil, hasPendingInvite else { return }
        inviteTask = Task {
            defer { inviteTask = nil }
            do {
                let user = try await verifyAccount(force: true)
                let metadata: CKShare.Metadata
                if let pendingMetadata { metadata = pendingMetadata }
                else if let url = state.pendingInvite { metadata = try await transport.metadata(for: url) }
                else { return }
                let zone = metadata.share.recordID.zoneID
                if metadata.participantRole == .owner || metadata.ownerIdentity.userRecordID?.recordName == user {
                    invitationMessage = "This is your invitation. Other family members must open it on their phones."
                } else {
                    if metadata.participantStatus != .accepted { try await transport.accept(metadata) }
                    guard accountID == user else { throw CKError(.notAuthenticated) }
                    activate(CircleScope(zoneName: zone.zoneName, ownerName: zone.ownerName, isOwner: false))
                    invitationMessage = "You joined the family circle."
                }
                state.pendingInvite = nil
                pendingMetadata = nil
                try persist()
                inviteEventID = UUID()
                _ = await refresh()
            } catch {
                invitationMessage = "Could not join: " + Self.message(for: error)
                inviteEventID = UUID()
            }
        }
    }

    func activate(_ scope: CircleScope) {
        if state.scope != scope {
            if let previous = state.scope, let id = state.accountID { enqueueRemoval(scope: previous, accountID: id) }
            state.pendingLocation = nil
            state.arrival = nil
            lastPublishedLocation = nil
            lastPublishedAt = nil
            remoteMembers = []
            participants = []
        }
        state.scope = scope
        state.restoreAllowed = true
        saveOrReport()
        circleRevision += 1
    }

    func removePublishedLocation(completion: (() -> Void)? = nil) {
        publishingAllowed = false
        state.pendingLocation = nil
        state.arrival = nil
        lastPublishedLocation = nil
        lastPublishedAt = nil
        if let scope = state.scope, let id = state.accountID { enqueueRemoval(scope: scope, accountID: id) }
        saveOrReport()
        startSync()
        completion?()
    }

    func leaveCircle(completion: (() -> Void)? = nil) {
        removePublishedLocation()
        Task {
            defer { completion?() }
            do {
                guard let scope = state.scope else { return }
                _ = try await verifyAccount(force: true)
                try await transport.leave(scope)
                guard state.scope == scope else { return }
                state.scope = nil
                state.restoreAllowed = false
                state.removals.removeAll { $0.scope == scope }
                remoteMembers = []
                participants = []
                try persist()
                circleRevision += 1
                statusMessage = "You left the family circle."
            } catch { handle(error) }
        }
    }

    func cloudSharingChanged() { fetchSharedLocations() }

    private func refreshParticipants(in scope: CircleScope) async {
        do {
            let id = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: scope.zoneID)
            guard let share = try await transport.record(id, in: scope) as? CKShare, state.scope == scope else { return }
            participants = share.participants.enumerated().filter { $0.element.userIdentity.userRecordID?.recordName != accountID }.map { index, participant in
                let name = participant.userIdentity.nameComponents.map {
                    PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
                } ?? ""
                return CircleParticipant(id: participant.userIdentity.userRecordID?.recordName ?? "pending-\(index)",
                    name: name.isEmpty ? "Family member" : name, accepted: participant.acceptanceStatus == .accepted)
            }
        } catch { }
    }

    private func enqueueRemoval(scope: CircleScope, accountID: String) {
        let removal = PendingRemoval(scope: scope, accountID: accountID)
        if !state.removals.contains(removal) { state.removals.append(removal) }
    }

    func startSync() {
        guard state.pendingLocation != nil || !state.removals.isEmpty else { return }
        guard syncTask == nil else { return }
        retryTask?.cancel()
        syncTask = Task {
            defer { syncTask = nil }
            let lease = BackgroundUploadLease { [weak self] in self?.syncTask?.cancel() }
            defer { lease.end() }
            do {
                let id = try await verifyAccount()
                try await flushOutbox(accountID: id)
                retryAttempt = 0
            } catch is CancellationError { }
            catch { handle(error); scheduleRetry(error) }
        }
    }

    func syncNow() async {
        startSync()
        await syncTask?.value
    }

    private func updateFreshness() {
        remoteMembers = remoteMembers.map { member in
            var member = member
            let stale = Date().timeIntervalSince(member.lastLocationUpdate) > 180
            member.status = stale ? .offline : .live
            member.place = stale ? "Last known location" : "Shared location"
            member.tint = stale ? .gray : .green
            member.updatedAt = member.lastLocationUpdate.formatted(.relative(presentation: .named))
            return member
        }
    }

    func flushOutbox(accountID id: String) async throws {
        try Task.checkCancellation()
        while let removal = state.removals.first {
            guard removal.accountID == id else { state.removals.removeFirst(); try persist(); continue }
            try await transport.delete(CKRecord.ID(recordName: "location-" + id, zoneID: removal.scope.zoneID), in: removal.scope)
            state.removals.removeAll { $0 == removal }
            try persist()
        }
        while let pending = state.pendingLocation {
            try Task.checkCancellation()
            guard publishingAllowed else { return }
            if let expiry = pending.expiresAt, expiry <= Date() {
                publishingAllowed = false
                state.pendingLocation = nil
                enqueueRemoval(scope: pending.scope, accountID: id)
                try persist()
                try await flushOutbox(accountID: id)
                return
            }
            guard pending.accountID == id, pending.scope == state.scope,
                  pending.sample.isUsable(at: Date()) else {
                state.pendingLocation = nil; try persist(); return
            }
            let recordID = CKRecord.ID(recordName: "location-" + id, zoneID: pending.scope.zoneID)
            let record: CKRecord
            do { record = try await transport.record(recordID, in: pending.scope) }
            catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: "WhereaboutsLocation", recordID: recordID)
            }
            let address = await addressResolver(pending.sample.location)
            try Task.checkCancellation()
            guard publishingAllowed, state.pendingLocation?.id == pending.id, state.scope == pending.scope, accountID == id else { continue }
            if let expiry = pending.expiresAt, expiry <= Date() { continue }
            record["userRecordName"] = id as CKRecordValue
            record["displayName"] = pending.displayName as CKRecordValue
            record["latitude"] = pending.sample.latitude as CKRecordValue
            record["longitude"] = pending.sample.longitude as CKRecordValue
            record["horizontalAccuracy"] = pending.sample.accuracy as CKRecordValue
            record["address"] = address as CKRecordValue
            record["arrivedAt"] = pending.arrivedAt as CKRecordValue
            record["updatedAt"] = pending.sample.timestamp as CKRecordValue
            _ = try await transport.save(record, in: pending.scope)
            // A pause or circle switch during a save must remove that in-flight write.
            if !publishingAllowed || state.scope != pending.scope || accountID != id || pending.expiresAt.map({ $0 <= Date() }) == true {
                enqueueRemoval(scope: pending.scope, accountID: id)
                try persist()
                try await transport.delete(recordID, in: pending.scope)
                state.removals.removeAll { $0.scope == pending.scope && $0.accountID == id }
            } else {
                lastPublishedAt = pending.sample.timestamp
                lastPublishedLocation = pending.sample.location
                statusMessage = "Your location is shared."
            }
            if state.pendingLocation?.id == pending.id { state.pendingLocation = nil }
            try persist()
        }
    }

    private func scheduleRetry(_ error: Error) {
        guard !state.removals.isEmpty || state.pendingLocation != nil else { return }
        guard let ckError = error as? CKError,
              [.networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy, .serverRecordChanged].contains(ckError.code) else { return }
        retryAttempt += 1
        let delay = max(ckError.retryAfterSeconds ?? 0, min(300, pow(2, Double(min(retryAttempt, 8)))))
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            self?.startSync()
        }
    }

    private func persist() throws {
        if let storageError { throw storageError }
        try persistence.save(state)
    }

    @discardableResult private func saveOrReport() -> Bool {
        do { try persist(); return true } catch { handle(error); return false }
    }

    private func handle(_ error: Error) {
        statusMessage = Self.message(for: error)
        if let ck = error as? CKError {
            if [.zoneNotFound, .userDeletedZone, .permissionFailure].contains(ck.code) {
                remoteMembers = []
                participants = []
                state.scope = nil
                state.restoreAllowed = false
                state.pendingLocation = nil
                publishingAllowed = false
                try? persist()
                circleRevision += 1
            }
            if ck.code == .notAuthenticated { accountID = nil; verifiedAt = nil; publishingAllowed = false; remoteMembers = [] }
        }
    }

    static func message(for error: Error) -> String {
        guard let error = error as? CKError else { return error.localizedDescription }
        switch error.code {
        case .notAuthenticated: return "Sign in to iCloud in iPhone Settings, then retry."
        case .networkFailure, .networkUnavailable: return "Offline. Your latest location will retry when connected."
        case .zoneNotFound, .userDeletedZone, .permissionFailure: return "This circle is no longer available. Open a new invitation to reconnect."
        case .serverRejectedRequest, .constraintViolation: return "iCloud could not complete this request. Please retry."
        default: return error.localizedDescription
        }
    }

    static func member(from record: CKRecord) -> FamilyMember? {
        guard let name = record["displayName"] as? String, let lat = record["latitude"] as? Double,
              let lon = record["longitude"] as? Double, (-90...90).contains(lat), (-180...180).contains(lon),
              let updated = record["updatedAt"] as? Date else { return nil }
        let stale = Date().timeIntervalSince(updated) > 180
        return FamilyMember(id: record.recordID.zoneID.ownerName + "/" + record.recordID.recordName,
            name: name, phoneNumber: nil, emailAddress: nil, device: "iPhone", status: stale ? .offline : .live,
            place: stale ? "Last known location" : "Shared location", address: record["address"] as? String ?? "Address unavailable",
            batteryLevel: -1, updatedAt: updated.formatted(.relative(presentation: .named)),
            arrivedAt: record["arrivedAt"] as? Date ?? updated, lastLocationUpdate: updated, isLocationShared: true,
            tint: stale ? .gray : .green, latitude: lat, longitude: lon, speed: nil, eta: nil)
    }

    private static func resolveAddress(_ location: CLLocation) async -> String {
        let fallback = String(format: "%.3f, %.3f", location.coordinate.latitude, location.coordinate.longitude)
        guard let place = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return fallback }
        let street = location.horizontalAccuracy < 1000 ? [place.subThoroughfare, place.thoroughfare].compactMap { $0 }.joined(separator: " ") : nil
        let parts = [street, place.locality, place.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? fallback : parts.joined(separator: ", ")
    }
}

@MainActor
private final class BackgroundUploadLease {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    init(onExpiration: @escaping @MainActor () -> Void) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Whereabouts location sync") { [weak self] in
            Task { @MainActor in
                onExpiration()
                self?.end()
            }
        }
    }
    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

struct CircleParticipant: Identifiable {
    var id: String
    var name: String
    var accepted: Bool
}

enum SharingError: LocalizedError {
    case alreadyJoined
    var errorDescription: String? { "You already belong to a family circle. The owner manages invitations." }
}
