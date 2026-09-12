import CloudKit
import ContactsUI
import SwiftUI
import UIKit

struct PeopleView: View {
    @Binding var members: [FamilyMember]
    @Binding var selectedMember: FamilyMember?
    @ObservedObject var cloudSharing: CloudLocationSharingStore
    @ObservedObject var locationSharing: LocationSharingStore
    var onShowMap: () -> Void = {}
    @State private var preparedShare: PreparedShare?
    @State private var inviteError: String?
    @State private var isEnteringInvite = false
    @State private var isConfirmingSwitch = false
    @State private var isInvitingFamily = false

    var body: some View {
        List {
            invitationSection
            Section("Family circle") {
                LabeledContent("Connection", value: cloudSharing.circleConnectionSummary)
                if (!cloudSharing.hasActiveCircle || cloudSharing.isCircleOwner) && !cloudSharing.hasPendingInvite {
                    Button { isInvitingFamily = true } label: {
                        Label("Invite family", systemImage: "person.badge.plus")
                    }
                    .disabled(cloudSharing.isPreparingShare)
                }
                if cloudSharing.isCircleOwner && !cloudSharing.hasPendingInvite {
                    Button {
                        cloudSharing.prepareShare { result in
                            switch result {
                            case .success(let value): preparedShare = PreparedShare(share: value.share, container: value.container)
                            case .failure(let error): inviteError = CloudLocationSharingStore.message(for: error)
                            }
                        }
                    } label: {
                        Label(cloudSharing.isPreparingShare ? "Preparing..." : "Manage members",
                              systemImage: "person.2.badge.gearshape")
                    }
                    .disabled(cloudSharing.isPreparingShare)
                } else if cloudSharing.hasActiveCircle && !cloudSharing.isCircleOwner {
                    Label("Joined family circle", systemImage: "person.2.fill")
                }
                Button { isEnteringInvite = true } label: {
                    Label("Join with invitation", systemImage: "link.badge.plus")
                }
                ForEach(cloudSharing.participants) { person in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.name).font(.headline)
                        Text(participantStatus(person)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }

            if cloudSharing.hasActiveCircle {
                Section("This iPhone") {
                    Toggle("Share my location", isOn: Binding(get: { locationSharing.isLiveSharingEnabled }, set: { enabled in
                        if enabled { locationSharing.enableSharing() } else { locationSharing.stopSharing() }
                    }))
                    LabeledContent("Status", value: phoneStatus)
                    LabeledContent("Location access", value: locationSharing.permissionSummary)
                    if locationSharing.authorizationStatus == .notDetermined {
                        Button("Allow location") { locationSharing.requestWhenInUsePermission() }
                    } else if locationSharing.authorizationStatus == .authorizedWhenInUse {
                        Button("Allow sharing in the background") { locationSharing.requestAlwaysPermission() }
                    } else if locationSharing.authorizationStatus == .denied || locationSharing.authorizationStatus == .restricted {
                        Button("Open iPhone Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                    LabeledContent("Last sent", value: cloudSharing.lastPublishedAt?.formatted(.relative(presentation: .named)) ?? "Not sent yet")
                    if let error = locationSharing.locationErrorMessage ?? cloudSharing.uploadError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    Button {
                        locationSharing.refreshCurrentLocation(requestPermission: false)
                        cloudSharing.fetchSharedLocations()
                    } label: { Label("Retry connection", systemImage: "arrow.clockwise") }
                }
            }

            Section {
                if cloudSharing.remoteMembers.isEmpty {
                    ContentUnavailableView("No shared locations yet", systemImage: "location.slash")
                }
                ForEach(cloudSharing.remoteMembers) { member in
                    Button {
                        selectedMember = member
                        onShowMap()
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(member.tint)
                            VStack(alignment: .leading) {
                                Text(member.name).foregroundStyle(.primary)
                                Text(member.place).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(member.lastLocationUpdate, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: { Text("Shared locations") }
              footer: {
                  Text(cloudSharing.connectionError ?? (cloudSharing.remoteMembers.isEmpty
                       ? "No location has been received from another phone."
                       : cloudSharing.statusMessage))
              }
            Section("Connection details") {
                LabeledContent("iCloud", value: cloudSharing.accountID == nil ? "Not connected" : "Connected")
                LabeledContent("Last circle check", value: cloudSharing.lastReceivedAt?.formatted(.relative(presentation: .named)) ?? "Not yet")
                LabeledContent("Version", value: appVersion)
            }
        }
        .navigationTitle("People")
        .onChange(of: cloudSharing.inviteEventID) { _, _ in
            if cloudSharing.hasPendingInvite {
                preparedShare = nil
                isInvitingFamily = false
                isEnteringInvite = false
            }
        }
        .refreshable { _ = await cloudSharing.refresh() }
        .sheet(item: $preparedShare) { prepared in
            CloudInviteController(share: prepared.share, container: prepared.container, store: cloudSharing) { inviteError = $0 }
        }
        .sheet(isPresented: $isEnteringInvite) {
            InvitationEntryView { text in
                cloudSharing.receiveInvitationLink(text)
                cloudSharing.inspectPendingInvite()
            }
        }
        .sheet(isPresented: $isInvitingFamily) { InviteFamilyView(cloud: cloudSharing) }
        .confirmationDialog("Switch family circles?", isPresented: $isConfirmingSwitch, titleVisibility: .visible) {
            Button("Switch and join") { cloudSharing.acceptPendingInvite() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sharing on this iPhone will pause. Its last location in the previous circle will be removed when connected. The previous circle will not be deleted.")
        }
        .alert("Invitation unavailable", isPresented: Binding(get: { inviteError != nil }, set: { if !$0 { inviteError = nil } })) {
            Button("OK") { inviteError = nil }
        } message: { Text(inviteError ?? "") }
    }

    @ViewBuilder private var invitationSection: some View {
        if cloudSharing.hasPendingInvite || cloudSharing.invitationMessage != nil {
            Section("Family invitation") {
                if cloudSharing.invitationPhase.isBusy {
                    HStack {
                        ProgressView().frame(width: 24, height: 24)
                        Text(cloudSharing.invitationPhase == .joining ? "Confirming circle access..." : "Checking invitation...")
                    }
                }
                if cloudSharing.invitationPhase == .ready, let invitation = cloudSharing.invitation {
                    LabeledContent("From", value: invitation.ownerName)
                    Button {
                        if cloudSharing.invitationChangesCircle { isConfirmingSwitch = true }
                        else { cloudSharing.acceptPendingInvite() }
                    } label: { Label("Join family circle", systemImage: "person.2.badge.plus") }
                    Text("This iPhone's location stays private until you enable sharing.").font(.footnote).foregroundStyle(.secondary)
                }
                if let message = cloudSharing.invitationMessage {
                    Text(message).foregroundStyle(cloudSharing.invitationPhase == .failed ? .red : .primary)
                }
                if cloudSharing.hasPendingInvite && [.failed, .idle].contains(cloudSharing.invitationPhase) {
                    Button { cloudSharing.inspectPendingInvite() } label: {
                        Label("Check invitation again", systemImage: "arrow.clockwise")
                    }
                }
                Button(cloudSharing.invitationPhase == .joined ? "Done" : "Dismiss invitation", role: .cancel) {
                    cloudSharing.cancelInvitation()
                }
            }
        }
    }

    private var phoneStatus: String {
        guard locationSharing.isLiveSharingEnabled else { return "Sharing paused" }
        guard cloudSharing.isCircleVerified else { return "Waiting for circle connection" }
        if [.denied, .restricted, .notDetermined].contains(locationSharing.authorizationStatus) { return "Location permission needed" }
        if cloudSharing.uploadError != nil { return "Location not sent" }
        if cloudSharing.hasPendingUpload { return "Sending location" }
        guard let last = cloudSharing.lastPublishedAt else { return "Waiting for first location" }
        if Date().timeIntervalSince(last) > 180 { return "Last location is out of date" }
        return locationSharing.authorizationStatus == .authorizedAlways ? "Location sent" : "Sent; background access needed"
    }

    private func participantStatus(_ person: CircleParticipant) -> String {
        guard person.accepted else { return "Invitation not accepted yet" }
        return cloudSharing.remoteMembers.contains(where: { $0.id.hasSuffix("/location-" + person.id) })
            ? "Joined; location received" : "Joined; no location received"
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
    }
}

private struct InviteFamilyView: View {
    @ObservedObject var cloud: CloudLocationSharingStore
    @Environment(\.dismiss) private var dismiss
    @State private var recipient = ""
    @State private var error: String?
    @State private var entryURL: URL?
    @State private var choosingContact = false
    @State private var showingDelivery = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Apple Account email or phone", text: $recipient)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.emailAddress).privacySensitive()
                        .disabled(cloud.isPreparingShare)
                    Button { choosingContact = true } label: { Label("Choose from Contacts", systemImage: "person.crop.circle") }
                        .disabled(cloud.isPreparingShare)
                    Button {
                        do {
                            let person = try InvitationRecipient(recipient)
                            error = nil
                            entryURL = nil
                            cloud.prepareShare(recipient: person) { result in
                                switch result {
                                case .success(let value):
                                    entryURL = value.entryURL
                                    showingDelivery = value.entryURL != nil
                                case .failure(let failure): error = CloudLocationSharingStore.message(for: failure)
                                }
                            }
                        } catch { self.error = error.localizedDescription }
                    } label: {
                        HStack {
                            if cloud.isPreparingShare { ProgressView() }
                            Label(cloud.isPreparingShare ? "Preparing invitation..." : "Prepare and send invitation", systemImage: "paperplane")
                        }
                    }
                    .disabled(cloud.isPreparingShare || recipient.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: { Text("Family member") }
                  footer: { Text("Use the Apple Account shown in their iPhone Settings. Only that account is invited. Joining does not turn on location sharing.") }
                if let error { Section { Text(error).foregroundStyle(.red) } }
                if let entryURL {
                    Section("Invitation ready") {
                        ShareLink(item: entryURL) { Label("Send invitation again", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .navigationTitle("Invite family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(cloud.isPreparingShare) } }
            .onChange(of: recipient) { _, _ in entryURL = nil; error = nil }
            .sheet(isPresented: $choosingContact) {
                InvitationContactPicker { value in recipient = value; choosingContact = false }
            }
            .sheet(isPresented: $showingDelivery) {
                if let entryURL { InvitationDeliveryController(url: entryURL) }
            }
            .interactiveDismissDisabled(cloud.isPreparingShare)
        }
    }
}

private struct InvitationDeliveryController: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: ["Join my Whereabouts family circle: \(url.absoluteString)"], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct InvitationContactPicker: UIViewControllerRepresentable {
    let select: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(select: select) }
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactEmailAddressesKey, CNContactPhoneNumbersKey]
        picker.predicateForSelectionOfContact = NSPredicate(value: false)
        picker.predicateForSelectionOfProperty = NSPredicate(format: "key IN %@", [CNContactEmailAddressesKey, CNContactPhoneNumbersKey])
        return picker
    }
    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}
    final class Coordinator: NSObject, CNContactPickerDelegate {
        let select: (String) -> Void
        init(select: @escaping (String) -> Void) { self.select = select }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect property: CNContactProperty) {
            if let email = property.value as? String { select(email) }
            else if let phone = property.value as? CNPhoneNumber { select(phone.stringValue) }
        }
    }
}

private struct InvitationEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    let submit: (String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("iCloud invitation") {
                    TextField("Invitation link", text: $link, axis: .vertical)
                        .lineLimit(2...5).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL).privacySensitive()
                    PasteButton(payloadType: String.self) { values in link = values.first ?? "" }
                    Button("Review invitation") { submit(link); dismiss() }
                        .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Join family")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct PreparedShare: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

private struct CloudInviteController: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let store: CloudLocationSharingStore
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(store: store, onError: onError) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let store: CloudLocationSharingStore
        let onError: (String) -> Void
        init(store: CloudLocationSharingStore, onError: @escaping (String) -> Void) {
            self.store = store
            self.onError = onError
        }
        func itemTitle(for csc: UICloudSharingController) -> String? { "Whereabouts Family Circle" }
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onError(CloudLocationSharingStore.message(for: error))
        }
        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { store.cloudSharingChanged() }
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { store.cloudSharingChanged() }
    }
}
