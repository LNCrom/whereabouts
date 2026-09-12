import CloudKit
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = SharingRuntime.shared
        application.registerForRemoteNotifications()
        Task { await SharingRuntime.shared.refresh() }
        return true
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        SharingRuntime.shared.receiveInvite(cloudKitShareMetadata)
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let metadata = options.cloudKitShareMetadata { SharingRuntime.shared.receiveInvite(metadata) }
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SharingSceneDelegate.self
        return configuration
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { completionHandler(.noData); return }
        Task {
            let changed = await SharingRuntime.shared.cloud.refresh()
            completionHandler(changed ? .newData : .noData)
        }
    }
}

final class SharingSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata { SharingRuntime.shared.receiveInvite(metadata) }
        else if let url = connectionOptions.urlContexts.first?.url { SharingRuntime.shared.receiveInvitationURL(url) }
        else if let url = connectionOptions.userActivities.first?.webpageURL { SharingRuntime.shared.receiveInvitationURL(url) }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        SharingRuntime.shared.receiveInvite(metadata)
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url { SharingRuntime.shared.receiveInvitationURL(url) }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        if let url = userActivity.webpageURL { SharingRuntime.shared.receiveInvitationURL(url) }
    }
}
