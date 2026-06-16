import SwiftUI

struct ContentView: View {
    @StateObject private var locationSharing = LocationSharingStore()
    @State private var familyMembers = FamilyFixtures.members
    @State private var selectedMember = FamilyFixtures.members[0]
    @State private var selectedTab: AppTab = .map

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardView(
                    members: familyMembers,
                    selectedMember: $selectedMember,
                    locationSharing: locationSharing
                )
            }
            .tabItem {
                Label("Map", systemImage: "location.fill")
            }
            .tag(AppTab.map)

            NavigationStack {
                PeopleView(members: $familyMembers, selectedMember: $selectedMember)
            }
            .tabItem {
                Label("People", systemImage: "person.2.fill")
            }
            .tag(AppTab.people)

            NavigationStack {
                SettingsView(locationSharing: locationSharing)
            }
            .tabItem {
                Label("Privacy", systemImage: "shield.checkered")
            }
            .tag(AppTab.privacy)
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
        ContentView()
    }
}
