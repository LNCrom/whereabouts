import CloudKit
import SwiftUI
import UIKit

struct PeopleView: View {
    @Binding var members: [FamilyMember]
    @Binding var selectedMember: FamilyMember?
    @ObservedObject var cloudSharing: CloudLocationSharingStore

    @State private var preparedInvite: PreparedWhereaboutsInvite?
    @State private var inviteErrorMessage: String?

    var body: some View {
        List {
            Section {
                Button {
                    prepareCloudInvite()
                } label: {
                    if cloudSharing.isPreparingShare {
                        Label("Preparing invite...", systemImage: "icloud.and.arrow.up")
                    } else {
                        Label(cloudSharing.sharingTitle, systemImage: "person.2.badge.plus")
                    }
                }
                .disabled(cloudSharing.isPreparingShare)

                Label("Apple sends and approves the iCloud invite", systemImage: "checkmark.icloud.fill")
                Label("Approved members publish location into the shared circle", systemImage: "location.fill")
            } header: {
                Text("Invite link")
            } footer: {
                Text("\(cloudSharing.statusMessage) Send this link only to people you want in your Whereabouts circle.")
            }

            Section("Shared phones") {
                if cloudSharing.remoteMembers.isEmpty {
                    ContentUnavailableView(
                        "No shared phones yet",
                        systemImage: "iphone.gen3.radiowaves.left.and.right",
                        description: Text("Send the invite link. After someone opens it in Whereabouts and allows location, they appear here.")
                    )
                } else {
                    ForEach(cloudSharing.remoteMembers) { member in
                        Button {
                            selectedMember = member
                        } label: {
                            PersonRow(member: member, isSelected: member.id == selectedMember?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("People")
        .sheet(item: $preparedInvite) { invite in
            ActivityController(items: [
                "Join my Whereabouts family circle to share live locations.",
                invite.url
            ])
        }
        .alert("Could not prepare invite", isPresented: inviteErrorBinding) {
            Button("OK", role: .cancel) {
                inviteErrorMessage = nil
            }
        } message: {
            Text(inviteErrorMessage ?? "Try again in a moment.")
        }
    }

    private func prepareCloudInvite() {
        cloudSharing.prepareShare { result in
            switch result {
            case .success(let preparedShare):
                guard let url = preparedShare.share.url else {
                    inviteErrorMessage = "Whereabouts created the iCloud share, but Apple did not return an invite link. Try again in a moment."
                    return
                }

                preparedInvite = PreparedWhereaboutsInvite(url: url)
            case .failure(let error):
                inviteErrorMessage = error.localizedDescription
            }
        }
    }

    private var inviteErrorBinding: Binding<Bool> {
        Binding {
            inviteErrorMessage != nil
        } set: { isPresented in
            if isPresented == false {
                inviteErrorMessage = nil
            }
        }
    }
}

private struct PreparedWhereaboutsInvite: Identifiable {
    let id = UUID()
    let url: URL
}

private struct PersonRow: View {
    var member: FamilyMember
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(String(member.name.prefix(1)))
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(member.tint, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(member.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(member.isLocationShared ? member.place : "Invite required before live sharing")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(member.status.rawValue)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(member.status.color)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(member.status.color.opacity(0.12), in: Capsule())

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ActivityController: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}

struct PeopleView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            PeopleView(
                members: .constant(FamilyFixtures.members),
                selectedMember: .constant(FamilyFixtures.members[0]),
                cloudSharing: CloudLocationSharingStore()
            )
        }
    }
}
