import Contacts
import ContactsUI
import CloudKit
import SwiftUI
import UIKit

struct PeopleView: View {
    @Binding var members: [FamilyMember]
    @Binding var selectedMember: FamilyMember?
    @ObservedObject var cloudSharing: CloudLocationSharingStore

    @State private var isContactPickerPresented = false
    @State private var isCloudSharingPresented = false

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
                Button {
                    isCloudSharingPresented = true
                } label: {
                    Label(cloudSharing.sharingTitle, systemImage: "person.2.badge.plus")
                }

                Label("Apple sends and approves the iCloud invite", systemImage: "checkmark.icloud.fill")
                Label("Approved members publish location into the shared circle", systemImage: "location.fill")
            } header: {
                Text("Whereabouts sharing")
            } footer: {
                Text(cloudSharing.statusMessage)
            }

            Section("Family Circle") {
                if members.isEmpty && cloudSharing.remoteMembers.isEmpty {
                    ContentUnavailableView(
                        "No people yet",
                        systemImage: "person.2",
                        description: Text("Select someone from Contacts to send a Whereabouts invite.")
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

                    ForEach(members) { member in
                        VStack(spacing: 8) {
                            Button {
                                selectedMember = member
                            } label: {
                                PersonRow(member: member, isSelected: member.id == selectedMember?.id)
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
        .sheet(isPresented: $isCloudSharingPresented) {
            CloudSharingController(cloudSharing: cloudSharing)
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
        isCloudSharingPresented = true
    }

    private func removeMembers(at offsets: IndexSet) {
        let removedIDs = offsets.map { members[$0].id }
        members.remove(atOffsets: offsets)

        if let selectedMember, removedIDs.contains(selectedMember.id) {
            self.selectedMember = members.first ?? cloudSharing.remoteMembers.first
        }
    }

    private var nextTint: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
        return colors[members.count % colors.count]
    }
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

private struct CloudSharingController: UIViewControllerRepresentable {
    @ObservedObject var cloudSharing: CloudLocationSharingStore

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController { controller, completion in
            cloudSharing.prepareShare(controller, completion: completion)
        }
        cloudSharing.configure(controller)
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {
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
