import XCTest
@testable import FamilyLocator

@MainActor
final class LocationSharingStoreTests: XCTestCase {
    func testSharingPreferencesPersistAndTimedWindowExpires() {
        let suiteName = "WhereaboutsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LocationSharingStore(defaults: defaults)
        store.allowsPreciseSharing = false
        store.sharingWindow = .oneHour
        store.isLiveSharingEnabled = true

        let reloaded = LocationSharingStore(defaults: defaults)
        XCTAssertFalse(reloaded.allowsPreciseSharing)
        XCTAssertEqual(reloaded.sharingWindow, .oneHour)
        XCTAssertTrue(reloaded.isLiveSharingEnabled)

        reloaded.enforceSharingExpiration(now: Date().addingTimeInterval(61 * 60))
        XCTAssertFalse(reloaded.isLiveSharingEnabled)
    }

    func testStopSharingPersistsImmediately() {
        let suiteName = "WhereaboutsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = LocationSharingStore(defaults: defaults)
        store.stopSharing()

        XCTAssertFalse(LocationSharingStore(defaults: defaults).isLiveSharingEnabled)
    }
}
