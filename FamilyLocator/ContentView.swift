import SwiftUI

struct ContentView: View {
    @ObservedObject var auth: AuthStore

    @StateObject private var locationSharing = LocationSharingStore()
    @StateObject private var cloudSharing = CloudLocationSharingStore()
    @State private var familyMembers: [FamilyMember] = []
    @State private var selectedMember: FamilyMember?
    @State private var selectedTab: AppTab = .map
    @State private var handledInviteEventID: UUID?
    private let refreshTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    private var visibleMembers: [FamilyMember] {
        familyMembers + cloudSharing.remoteMembers
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(
                    members: visibleMembers,
                    selectedMember: $selectedMember,
                    locationSharing: locationSharing,
                    cloudSharing: cloudSharing
                )
            }
            .tabItem {
                Label("Map", systemImage: "location.fill")
            }
            .tag(AppTab.map)

            NavigationStack {
                PeopleView(
                    members: $familyMembers,
                    selectedMember: $selectedMember,
                    cloudSharing: cloudSharing
                )
            }
            .tabItem {
                Label("People", systemImage: "person.2.fill")
            }
            .tag(AppTab.people)

            NavigationStack {
                SettingsView(auth: auth, locationSharing: locationSharing, cloudSharing: cloudSharing)
            }
            .tabItem {
                Label("Privacy", systemImage: "shield.checkered")
            }
            .tag(AppTab.privacy)
        }
        .onReceive(locationSharing.$currentLocation.compactMap { $0 }) { location in
            guard locationSharing.canShareLocation else { return }
            cloudSharing.publish(location: location, displayName: auth.profile?.displayName)
        }
        .onReceive(cloudSharing.$remoteMembers) { members in
            updateSelectionIfNeeded(with: familyMembers + members)
        }
        .onReceive(cloudSharing.$inviteEventID.compactMap { $0 }) { eventID in
            handleInviteEvent(eventID)
        }
        .onReceive(refreshTimer) { _ in
            guard auth.canEnterApp else { return }
            cloudSharing.fetchSharedLocations()
        }
        .onAppear {
            locationSharing.refreshCurrentLocation()
            cloudSharing.fetchSharedLocations()
            if let inviteEventID = cloudSharing.inviteEventID {
                handleInviteEvent(inviteEventID)
            }
            updateSelectionIfNeeded(with: visibleMembers)
        }
    }

    private func handleInviteEvent(_ eventID: UUID) {
        guard handledInviteEventID != eventID else { return }
        handledInviteEventID = eventID
        selectedTab = .people

        locationSharing.refreshCurrentLocation()

        if locationSharing.canShareLocation, let currentLocation = locationSharing.currentLocation {
            cloudSharing.publish(location: currentLocation, displayName: auth.profile?.displayName)
        } else {
            cloudSharing.fetchSharedLocations()
        }
    }

    private func updateSelectionIfNeeded(with members: [FamilyMember]) {
        guard selectedMember == nil || members.contains(where: { $0.id == selectedMember?.id }) == false else { return }
        selectedMember = members.first
    }
}

private enum AppTab {
    case map
    case people
    case privacy
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(auth: AuthStore())
    }
}
