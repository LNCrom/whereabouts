import CloudKit
import SwiftUI
import UIKit

struct PeopleView: View {
    @Binding var members: [FamilyMember]
    @Binding var selectedMember: FamilyMember?
    @ObservedObject var cloudSharing: CloudLocationSharingStore
    @ObservedObject var locationSharing: LocationSharingStore
    @State private var preparedShare: PreparedShare?
    @State private var inviteError: String?

    var body: some View {
        List {
            if let message = cloudSharing.invitationMessage {
                Section {
                    Text(message)
                    if cloudSharing.hasPendingInvite {
                        Button("Retry joining") { cloudSharing.acceptPendingInvite() }
                    }
                }
            }
            Section("Family circle") {
                if !cloudSharing.hasActiveCircle || cloudSharing.isCircleOwner {
                    Button {
                        cloudSharing.prepareShare { result in
                            switch result {
                            case .success(let value): preparedShare = PreparedShare(share: value.share, container: value.container)
                            case .failure(let error): inviteError = CloudLocationSharingStore.message(for: error)
                            }
                        }
                    } label: {
                        Label(cloudSharing.isPreparingShare ? "Preparing invitation..." : cloudSharing.sharingTitle,
                              systemImage: "person.badge.plus")
                    }
                    .disabled(cloudSharing.isPreparingShare)
                } else {
                    Label("Joined family circle", systemImage: "person.2.fill")
                }
                ForEach(cloudSharing.participants) { person in
                    LabeledContent(person.name, value: person.accepted ? "Joined" : "Invitation pending")
                }
            }

            if cloudSharing.hasActiveCircle {
                Section("This iPhone") {
                    Toggle("Share my location", isOn: $locationSharing.isLiveSharingEnabled)
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
                }
            }

            Section {
                if cloudSharing.remoteMembers.isEmpty {
                    ContentUnavailableView("No shared locations yet", systemImage: "location.slash")
                }
                ForEach(cloudSharing.remoteMembers) { member in
                    Button {
                        selectedMember = member
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
              footer: { Text(cloudSharing.statusMessage) }
        }
        .navigationTitle("People")
        .refreshable { _ = await cloudSharing.refresh() }
        .sheet(item: $preparedShare) { prepared in
            CloudInviteController(share: prepared.share, container: prepared.container, store: cloudSharing) { inviteError = $0 }
        }
        .alert("Invitation unavailable", isPresented: Binding(get: { inviteError != nil }, set: { if !$0 { inviteError = nil } })) {
            Button("OK") { inviteError = nil }
        } message: { Text(inviteError ?? "") }
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
