import SwiftUI
import UIKit

struct SettingsView: View {
    @ObservedObject var auth: AuthStore
    @ObservedObject var locationSharing: LocationSharingStore
    @ObservedObject var cloudSharing: CloudLocationSharingStore
    @State private var isConfirmingCircleExit = false

    var body: some View {
        List {
            Section {
                PrivacyHeader(auth: auth, locationSharing: locationSharing, cloudSharing: cloudSharing)
            }

            Section("Account") {
                PermissionRow(
                    title: "Signed in as",
                    value: auth.profile?.displayName ?? "Unknown",
                    systemImage: "person.crop.circle.fill",
                    tint: .blue
                )

                Button(role: .destructive) {
                    locationSharing.stopSharing()
                    cloudSharing.removePublishedLocation {
                        auth.signOut()
                    }
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section("Sharing") {
                Toggle(isOn: $locationSharing.isLiveSharingEnabled) {
                    Label("Live location", systemImage: "location.fill")
                }

                Picker("Share duration", selection: $locationSharing.sharingWindow) {
                    ForEach(LocationSharingStore.SharingWindow.allCases) { window in
                        Text(window.rawValue).tag(window)
                    }
                }

                Toggle(isOn: $locationSharing.allowsPreciseSharing) {
                    Label("Precise sharing", systemImage: "scope")
                }

                Text("Timed sharing stops location updates automatically. You can also pause sharing immediately at any time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                PermissionRow(
                    title: "Location",
                    value: locationSharing.permissionSummary,
                    systemImage: "location.circle.fill",
                    tint: .blue
                )

                Button {
                    locationSharing.requestWhenInUsePermission()
                } label: {
                    Label("Allow location while using", systemImage: "hand.tap.fill")
                }

                Button {
                    locationSharing.requestAlwaysPermission()
                } label: {
                    Label("Allow background sharing", systemImage: "location.badge.plus")
                }

                Button {
                    openAppSettings()
                } label: {
                    Label("Open iOS Settings", systemImage: "gear")
                }
            }

            Section {
                PermissionRow(
                    title: "iCloud circle",
                    value: cloudSharing.circleConnectionSummary,
                    systemImage: "icloud.fill",
                    tint: .blue
                )

                PermissionRow(
                    title: "Shared people",
                    value: "\(cloudSharing.remoteMembers.count)",
                    systemImage: "person.2.fill",
                    tint: .green
                )

                Button {
                    locationSharing.refreshCurrentLocation()
                    cloudSharing.fetchSharedLocations()
                } label: {
                    Label("Refresh Whereabouts sharing", systemImage: "arrow.clockwise")
                }

                if cloudSharing.hasActiveCircle {
                    Button(role: .destructive) {
                        isConfirmingCircleExit = true
                    } label: {
                        Label(cloudSharing.isCircleOwner ? "Delete Whereabouts Circle" : "Leave Whereabouts Circle", systemImage: "person.crop.circle.badge.minus")
                    }
                }
            } header: {
                Text("Whereabouts Circle")
            } footer: {
                Text(cloudSharing.statusMessage)
            }

            Section {
                PermissionRow(
                    title: "Core Location",
                    value: "Used by this app",
                    systemImage: "location.north.line.fill",
                    tint: .green
                )

                PermissionRow(
                    title: "iCloud sharing",
                    value: "Whereabouts circle",
                    systemImage: "icloud.fill",
                    tint: .blue
                )

                PermissionRow(
                    title: "Find My",
                    value: "No public people API",
                    systemImage: "magnifyingglass.circle.fill",
                    tint: .secondary
                )
            } header: {
                Text("Apple services")
            } footer: {
                Text("Whereabouts can use iOS location permission and iCloud for users who install and approve the app. Apple does not provide third-party access to Find My people locations.")
            }
        }
        .navigationTitle("Privacy")
        .confirmationDialog(
            cloudSharing.isCircleOwner ? "Delete this Whereabouts circle?" : "Leave this Whereabouts circle?",
            isPresented: $isConfirmingCircleExit,
            titleVisibility: .visible
        ) {
            Button(cloudSharing.isCircleOwner ? "Delete Circle and Shared Locations" : "Leave Circle", role: .destructive) {
                locationSharing.stopSharing()
                cloudSharing.leaveCircle()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(cloudSharing.isCircleOwner
                 ? "This deletes the CloudKit circle and removes access for every participant. This cannot be undone."
                 : "Your published location will be removed and this device will forget the circle.")
        }
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(settingsURL)
    }
}

private struct PrivacyHeader: View {
    @ObservedObject var auth: AuthStore
    @ObservedObject var locationSharing: LocationSharingStore
    @ObservedObject var cloudSharing: CloudLocationSharingStore

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "shield.checkered")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 38, height: 38)
                .background(Color.green.opacity(0.14), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(auth.profile?.displayName ?? "Family sharing only")
                    .font(.headline)
                Text(headerMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var headerMessage: String {
        if locationSharing.isLiveSharingEnabled == false {
            return "Sharing is paused on this device."
        }

        if cloudSharing.hasActiveCircle {
            return "This device can publish to your Whereabouts circle."
        }

        return "Create or accept an invite before anyone can see this device."
    }
}

private struct PermissionRow: View {
    var title: String
    var value: String
    var systemImage: String
    var tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 28)

            Text(title)

            Spacer()

            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SettingsView(auth: AuthStore(), locationSharing: LocationSharingStore(), cloudSharing: CloudLocationSharingStore())
        }
    }
}
