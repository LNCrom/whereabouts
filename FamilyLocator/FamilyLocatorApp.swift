import SwiftUI

@main
struct FamilyLocatorApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var auth = SharingRuntime.shared.auth

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.canEnterApp {
                    ContentView(auth: auth, locationSharing: SharingRuntime.shared.location, cloudSharing: SharingRuntime.shared.cloud)
                } else if auth.isSignedIn {
                    LockView(auth: auth)
                } else {
                    SignInView(auth: auth)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                SharingRuntime.shared.phaseChanged(newPhase)
            }
        }
    }
}
