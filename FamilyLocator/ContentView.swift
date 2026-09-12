import SwiftUI

struct ContentView: View {
    @ObservedObject var auth: AuthStore

    @ObservedObject var locationSharing: LocationSharingStore
    @ObservedObject var cloudSharing: CloudLocationSharingStore
    @State private var familyMembers: [FamilyMember] = []
    @State private var selectedMember: FamilyMember?
    @State private var selectedTab: AppTab = .map
    @State private var handledInviteEventID: UUID?

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
                    cloudSharing: cloudSharing,
                    locationSharing: locationSharing,
                    onShowMap: { selectedTab = .map }
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
        .onReceive(cloudSharing.$remoteMembers) { members in
            updateSelectionIfNeeded(with: familyMembers + members)
        }
        .onReceive(cloudSharing.$inviteEventID.compactMap { $0 }) { eventID in
            handleInviteEvent(eventID)
        }
        .onAppear {
            locationSharing.refreshCurrentLocation(requestPermission: false)
            cloudSharing.fetchSharedLocations()
            if let inviteEventID = cloudSharing.inviteEventID {
                handleInviteEvent(inviteEventID)
            } else if !cloudSharing.hasActiveCircle || cloudSharing.remoteMembers.isEmpty {
                selectedTab = .people
            }
            updateSelectionIfNeeded(with: visibleMembers)
        }
    }

    private func handleInviteEvent(_ eventID: UUID) {
        guard handledInviteEventID != eventID else { return }
        handledInviteEventID = eventID
        selectedTab = .people

        locationSharing.refreshCurrentLocation(requestPermission: false)
    }

    private func updateSelectionIfNeeded(with members: [FamilyMember]) {
        selectedMember = members.first(where: { $0.id == selectedMember?.id }) ?? members.first
    }
}

private enum AppTab {
    case map
    case people
    case privacy
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(auth: AuthStore(), locationSharing: LocationSharingStore(), cloudSharing: CloudLocationSharingStore())
    }
}
