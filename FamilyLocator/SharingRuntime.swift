import CloudKit
import Combine
import Network
import SwiftUI

@MainActor
final class SharingRuntime: ObservableObject {
    static let shared = SharingRuntime()
    let auth: AuthStore
    let location: LocationSharingStore
    let cloud: CloudLocationSharingStore
    private var subscriptions: Set<AnyCancellable> = []
    private let network = NWPathMonitor()
    private var isForeground = false
    private var removedForConsentState = false

    init(auth: AuthStore? = nil, location: LocationSharingStore? = nil,
         cloud: CloudLocationSharingStore? = nil, monitorsEnabled: Bool = true) {
        let auth = auth ?? AuthStore()
        let location = location ?? LocationSharingStore()
        let cloud = cloud ?? CloudLocationSharingStore()
        self.auth = auth
        self.location = location
        self.cloud = cloud
        location.$currentLocation.compactMap { $0 }.sink { [weak self] fix in
            guard let self else { return }
            self.location.enforceSharingExpiration()
            self.reconcile()
            if self.location.canShareLocation {
                let sharedFix = LocationSample(fix, precise: self.location.allowsPreciseSharing).location
                self.cloud.publish(location: sharedFix, displayName: self.auth.profile?.displayName)
            }
        }.store(in: &subscriptions)
        // Published values emit before storage changes. Reconcile on the next main turn.
        Publishers.Merge3(location.objectWillChange, auth.objectWillChange, cloud.$circleRevision.map { _ in () }.eraseToAnyPublisher())
            .receive(on: DispatchQueue.main).sink { [weak self] in self?.reconcile() }.store(in: &subscriptions)
        location.$isLiveSharingEnabled.removeDuplicates().dropFirst().sink { [weak self] enabled in
            if !enabled { self?.cloud.removePublishedLocation() }
        }.store(in: &subscriptions)
        cloud.$accountChangedID.compactMap { $0 }.sink { [weak self] _ in
            self?.location.stopSharing()
            self?.auth.signOut()
        }.store(in: &subscriptions)
        auth.$isUnlocked.removeDuplicates().filter { $0 }.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.cloud.acceptPendingInvite()
        }.store(in: &subscriptions)
        if monitorsEnabled {
            NotificationCenter.default.publisher(for: .CKAccountChanged).sink { [weak self] _ in
                Task { @MainActor in self?.cloud.accountDidChange() }
            }.store(in: &subscriptions)
            network.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor in await self?.refresh() }
            }
            network.start(queue: DispatchQueue(label: "Whereabouts.network"))
            Timer.publish(every: 15, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                guard let self else { return }
                self.location.enforceSharingExpiration()
                if self.isForeground { Task { await self.refresh() } }
            }.store(in: &subscriptions)
        }
        reconcile()
    }

    func phaseChanged(_ phase: ScenePhase) {
        isForeground = phase == .active
        if phase == .background { auth.lock() }
        if phase == .active { Task { await refresh() } }
    }

    func refresh() async {
        location.enforceSharingExpiration()
        _ = await cloud.refresh()
        if let id = cloud.accountID {
            auth.bindLegacyProfile(to: id)
            if let profile = auth.profile, profile.id != id {
                location.stopSharing()
                auth.signOut()
            }
        }
        reconcile()
        if auth.canEnterApp { cloud.acceptPendingInvite() }
        if location.canShareLocation { location.refreshCurrentLocation(requestPermission: false) }
    }

    func reconcile() {
        let allowed = auth.isSignedIn && auth.profile?.id == cloud.accountID && cloud.accountID != nil && cloud.hasActiveCircle
        let consentEnded = !auth.isSignedIn || !location.isLiveSharingEnabled ||
            location.authorizationStatus == .denied || location.authorizationStatus == .restricted
        if consentEnded, !removedForConsentState, cloud.accountID != nil, cloud.hasActiveCircle {
            removedForConsentState = true
            cloud.removePublishedLocation()
        } else if !consentEnded { removedForConsentState = false }
        location.setSessionActive(allowed)
        cloud.setPublishingAllowed(allowed && location.canShareLocation,
            discardPending: !auth.isSignedIn || !location.isLiveSharingEnabled, expiresAt: location.sharingExpiresAt)
    }

    func receiveInvite(_ metadata: CKShare.Metadata) {
        cloud.receiveInvite(metadata)
        if auth.canEnterApp { cloud.acceptPendingInvite() }
    }
}
