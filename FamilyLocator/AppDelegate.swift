import CloudKit
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    private static var pendingShareMetadata: CKShare.Metadata?

    static func consumePendingShareMetadata() -> CKShare.Metadata? {
        let metadata = pendingShareMetadata
        pendingShareMetadata = nil
        return metadata
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Self.pendingShareMetadata = cloudKitShareMetadata

        NotificationCenter.default.post(
            name: CloudLocationSharingStore.acceptedShareMetadataNotification,
            object: cloudKitShareMetadata
        )
    }
}
