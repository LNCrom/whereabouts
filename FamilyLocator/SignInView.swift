import SwiftUI

struct SignInView: View {
    @ObservedObject var auth: AuthStore

    @State private var name = ""
    @State private var email = ""

    private var canContinue: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !auth.isAuthenticating
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 24)

                Image("WhereaboutsLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(spacing: 8) {
                    Text("Sign in to Whereabouts")
                        .font(.title.weight(.bold))

                    Text("Use the iCloud account on this iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 14) {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)

                }
                .textFieldStyle(.roundedBorder)

                Button {
                    auth.signIn(name: name, email: email)
                } label: {
                    Label(auth.isAuthenticating ? "Connecting..." : "Continue with iCloud", systemImage: "icloud")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(canContinue == false)

                if let error = auth.authenticationError {
                    Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Whereabouts")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SignInView_Previews: PreviewProvider {
    static var previews: some View {
        SignInView(auth: AuthStore())
    }
}
