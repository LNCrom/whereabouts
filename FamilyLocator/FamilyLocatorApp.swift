import SwiftUI

@main
struct FamilyLocatorApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            Group {
                if auth.canEnterApp {
                    ContentView(auth: auth)
                } else if auth.isSignedIn {
                    LockView(auth: auth)
                } else {
                    SignInView(auth: auth)
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    auth.lock()
                }
            }
        }
    }
}
