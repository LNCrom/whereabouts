import SwiftUI

struct LockView: View {
    @ObservedObject var auth: AuthStore

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("Whereabouts is locked")
                    .font(.title.weight(.bold))

                Text("Use Face ID or your device passcode to view family locations.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let authenticationError = auth.authenticationError {
                Text(authenticationError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                auth.unlock()
            } label: {
                Label("Unlock Whereabouts", systemImage: "faceid")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(role: .destructive) {
                auth.signOut()
            } label: {
                Text("Sign out")
            }

            Spacer()
        }
        .padding(24)
        .onAppear {
            auth.unlock()
        }
    }
}

struct LockView_Previews: PreviewProvider {
    static var previews: some View {
        LockView(auth: AuthStore())
    }
}
