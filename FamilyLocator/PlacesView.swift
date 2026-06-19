import Contacts
import ContactsUI
import MessageUI
import SwiftUI

struct PeopleView: View {
    @Binding var members: [FamilyMember]
    @Binding var selectedMember: FamilyMember
    @ObservedObject var cloudSharing: CloudLocationSharingStore

    @State private var isContactPickerPresented = false
    @State private var messageInvite: InviteMessage?
    @State private var shareInvite: InviteShare?

    var body: some View {
        List {
            Section {
                Button {
                    isContactPickerPresented = true
                } label: {
                    Label("Select from Contacts", systemImage: "person.crop.circle.badge.plus")
                }
            } footer: {
                Text("Whereabouts sharing uses iCloud and requires the other person to open Whereabouts and approve location permission. Apple does not let this app import Find My people locations.")
            }

            Section {
                Label("Send a Whereabouts invite link", systemImage: "paperplane.fill")
                Label("They open the link and approve sharing", systemImage: "checkmark.shield.fill")
                Label("Their app publishes location through iCloud", systemImage: "icloud.fill")
            } header: {
                Text("Whereabouts sharing")
            } footer: {
                Text(cloudSharing.statusMessage)
            }

            Section("Family Circle") {
                ForEach(members) { member in
                    VStack(spacing: 8) {
                        Button {
                            selectedMember = member
                        } label: {
                            PersonRow(member: member, isSelected: member.id == selectedMember.id)
                        }
                        .buttonStyle(.plain)

                        if member.isLocationShared == false {
                            Button {
                                invite(member)
                            } label: {
                                Label("Send Whereabouts invite", systemImage: "paperplane.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .onDelete(perform: removeMembers)
            }
        }
        .navigationTitle("People")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isContactPickerPresented = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Select family member from Contacts")
            }
        }
        .sheet(isPresented: $isContactPickerPresented) {
            ContactPicker { contact in
                addContact(contact)
            }
        }
        .sheet(item: $messageInvite) { invite in
            MessageComposer(invite: invite)
        }
        .sheet(item: $shareInvite) { invite in
            ShareSheet(items: [invite.message])
        }
    }

    private func addContact(_ contact: CNContact) {
        let name = CNContactFormatter.string(from: contact, style: .fullName) ?? "New Person"
        let phoneNumber = contact.phoneNumbers.first?.value.stringValue
        let emailAddress = contact.emailAddresses.first?.value as String?

        guard members.contains(where: { $0.name == name }) == false else { return }

        let member = FamilyMember(
            name: name,
            phoneNumber: phoneNumber,
            emailAddress: emailAddress,
            device: "Invite pending",
            status: .invited,
            place: "Waiting for shared location",
            address: "Waiting for shared location",
            batteryLevel: 0,
            updatedAt: "Not sharing",
            arrivedAt: Date(),
            lastLocationUpdate: Date(),
            isLocationShared: false,
            tint: nextTint,
            latitude: 30.2672,
            longitude: -97.7431,
            speed: nil,
            eta: nil
        )

        members.append(member)
        selectedMember = member
    }

    private func invite(_ member: FamilyMember) {
        let inviteURL = cloudSharing.inviteURL.absoluteString
        let message = """
        Can you share your location with me in Whereabouts?

        Open this invite on your iPhone:
        \(inviteURL)

        After you accept, allow Whereabouts to use your location so your live location appears on my map. Find My sharing cannot be imported into Whereabouts.
        """

        if MFMessageComposeViewController.canSendText(), let phoneNumber = member.phoneNumber {
            messageInvite = InviteMessage(recipient: phoneNumber, body: message)
        } else {
            shareInvite = InviteShare(message: message)
        }
    }

    private func removeMembers(at offsets: IndexSet) {
        let removedIDs = offsets.map { members[$0].id }
        members.remove(atOffsets: offsets)

        if removedIDs.contains(selectedMember.id), let firstMember = members.first {
            selectedMember = firstMember
        }
    }

    private var nextTint: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
        return colors[members.count % colors.count]
    }
}

private struct InviteMessage: Identifiable {
    let id = UUID()
    var recipient: String
    var body: String
}

private struct InviteShare: Identifiable {
    let id = UUID()
    var message: String
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

private struct ContactPicker: UIViewControllerRepresentable {
    var onSelect: (CNContact) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey, CNContactEmailAddressesKey]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var onSelect: (CNContact) -> Void

        init(onSelect: @escaping (CNContact) -> Void) {
            self.onSelect = onSelect
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onSelect(contact)
        }
    }
}

private struct MessageComposer: UIViewControllerRepresentable {
    var invite: InviteMessage
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = context.coordinator
        composer.recipients = [invite.recipient]
        composer.body = invite.body
        return composer
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        var dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            dismiss()
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            dismiss()
        }
        return controller
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
