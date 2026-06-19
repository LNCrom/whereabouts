import CloudKit
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        NotificationCenter.default.post(
            name: CloudLocationSharingStore.acceptedShareMetadataNotification,
            object: cloudKitShareMetadata
        )
    }
}
