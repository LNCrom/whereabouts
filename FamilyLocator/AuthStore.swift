import Foundation
import LocalAuthentication

@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var profile: UserProfile?
    @Published private(set) var isUnlocked = false
    @Published private(set) var authenticationError: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        profile = UserProfile.load(from: defaults)
    }

    var isSignedIn: Bool {
        profile != nil
    }

    var canEnterApp: Bool {
        isSignedIn && isUnlocked
    }

    func signIn(name: String, email: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = UserProfile(
            id: defaults.string(forKey: UserProfile.Keys.id) ?? UUID().uuidString,
            name: trimmedName,
            email: trimmedEmail
        )

        profile.save(to: defaults)
        self.profile = profile
        isUnlocked = true
        authenticationError = nil
    }

    func signOut() {
        UserProfile.clear(from: defaults)
        profile = nil
        isUnlocked = false
        authenticationError = nil
    }

    func lock() {
        guard isSignedIn else { return }
        isUnlocked = false
    }

    func unlock() {
        guard isSignedIn else { return }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authenticationError = error?.localizedDescription ?? "Device authentication is not available."
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Unlock Whereabouts to view your family circle."
        ) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }

                if success {
                    self.isUnlocked = true
                    self.authenticationError = nil
                } else {
                    self.authenticationError = error?.localizedDescription ?? "Whereabouts could not be unlocked."
                }
            }
        }
    }
}

struct UserProfile: Equatable {
    enum Keys {
        static let id = "whereabouts.auth.id"
        static let name = "whereabouts.auth.name"
        static let email = "whereabouts.auth.email"
    }

    var id: String
    var name: String
    var email: String

    var displayName: String {
        name.isEmpty ? email : name
    }

    static func load(from defaults: UserDefaults) -> UserProfile? {
        guard let id = defaults.string(forKey: Keys.id),
              let name = defaults.string(forKey: Keys.name),
              let email = defaults.string(forKey: Keys.email),
              email.isEmpty == false
        else {
            return nil
        }

        return UserProfile(id: id, name: name, email: email)
    }

    func save(to defaults: UserDefaults) {
        defaults.set(id, forKey: Keys.id)
        defaults.set(name, forKey: Keys.name)
        defaults.set(email, forKey: Keys.email)
    }

    static func clear(from defaults: UserDefaults) {
        defaults.removeObject(forKey: Keys.id)
        defaults.removeObject(forKey: Keys.name)
        defaults.removeObject(forKey: Keys.email)
    }
}
