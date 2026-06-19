import SwiftUI

struct ContentView: View {
    @ObservedObject var auth: AuthStore

    @StateObject private var locationSharing = LocationSharingStore()
    @StateObject private var cloudSharing = CloudLocationSharingStore()
    @State private var familyMembers = FamilyFixtures.members
    @State private var selectedMember = FamilyFixtures.members[0]
    @State private var selectedTab: AppTab = .map

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
        .onOpenURL { url in
            cloudSharing.acceptInvite(from: url)
            selectedTab = .privacy
        }
        .onReceive(locationSharing.$currentLocation.compactMap { $0 }) { location in
            guard locationSharing.canShareLocation else { return }
            cloudSharing.publish(location: location, displayName: auth.profile?.displayName)
        }
        .onAppear {
            cloudSharing.fetchSharedLocations()
        }
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
