import SwiftUI

struct SignInView: View {
    @ObservedObject var auth: AuthStore

    @State private var name = ""
    @State private var email = ""

    private var canContinue: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
        email.trimmingCharacters(in: .whitespacesAndNewlines).contains("@")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer(minLength: 24)

                Image("AppIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(spacing: 8) {
                    Text("Sign in to Whereabouts")
                        .font(.title.weight(.bold))

                    Text("Your profile identifies who is sharing location in your family circle.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 14) {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)

                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }
                .textFieldStyle(.roundedBorder)

                Button {
                    auth.signIn(name: name, email: email)
                } label: {
                    Label("Continue", systemImage: "person.crop.circle.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(canContinue == false)

                Text("Find My sharing still stays inside Apple Find My. Whereabouts uses its own signed-in family circle.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

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
