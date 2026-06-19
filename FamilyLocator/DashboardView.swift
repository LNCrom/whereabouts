import MapKit
import SwiftUI

struct DashboardView: View {
    var members: [FamilyMember]
    @Binding var selectedMember: FamilyMember?
    @ObservedObject var locationSharing: LocationSharingStore
    @ObservedObject var cloudSharing: CloudLocationSharingStore

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 30.2672, longitude: -97.7431),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    var body: some View {
        VStack(spacing: 0) {
            FamilyMapView(
                members: members,
                selectedMember: $selectedMember,
                cameraPosition: $cameraPosition
            )

            if let selectedMember {
                SelectedMemberCard(member: selectedMember)
                    .padding()
                    .background(Color(.systemGroupedBackground))
            } else {
                EmptyLocationCard()
                    .padding()
                    .background(Color(.systemGroupedBackground))
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Locations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    locationSharing.refreshCurrentLocation()
                    cloudSharing.fetchSharedLocations()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh this device location")
            }
        }
        .onChange(of: selectedMember) { _, newValue in
            guard let newValue else { return }
            focusMap(on: newValue, animated: true)
        }
        .onChange(of: members) { _, newValue in
            guard selectedMember == nil, let firstMember = newValue.first else { return }
            selectedMember = firstMember
            focusMap(on: firstMember, animated: false)
        }
        .onAppear {
            if let selectedMember {
                focusMap(on: selectedMember, animated: false)
            }
        }
    }

    private func focusMap(on member: FamilyMember, animated: Bool) {
        let update = {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: member.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
                )
            )
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.25), update)
        } else {
            update()
        }
    }
}

private struct FamilyMapView: View {
    var members: [FamilyMember]
    @Binding var selectedMember: FamilyMember?
    @Binding var cameraPosition: MapCameraPosition

    private var sharingMembers: [FamilyMember] {
        members.filter(\.isLocationShared)
    }

    private var selectedMemberID: Binding<FamilyMember.ID?> {
        Binding {
            guard let selectedMember, selectedMember.isLocationShared else { return nil }
            return selectedMember.id
        } set: { newValue in
            guard let newValue, let member = members.first(where: { $0.id == newValue }) else { return }
            selectedMember = member
        }
    }

    var body: some View {
        Map(position: $cameraPosition, selection: selectedMemberID) {
            UserAnnotation()

            ForEach(sharingMembers) { member in
                Marker(member.name, systemImage: "person.crop.circle.fill", coordinate: member.coordinate)
                    .tint(member.tint)
                    .tag(member.id)
            }
        }
        .mapControls {
            MapCompass()
            MapPitchToggle()
            MapUserLocationButton()
        }
        .mapStyle(.standard(elevation: .realistic))
        .overlay(alignment: .topLeading) {
            Label("Shared locations", systemImage: "dot.radiowaves.left.and.right")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .padding()
        }
        .overlay(alignment: .bottomLeading) {
            Text("Tap a person to see address and arrival details.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding()
        }
    }
}

private struct EmptyLocationCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 42, height: 42)
                    .background(Color.blue.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("No shared locations yet")
                        .font(.title3.weight(.bold))
                    Text("Invite someone from People, or open a Whereabouts invite on another device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SelectedMemberCard: View {
    var member: FamilyMember

    private let metricColumns = [
        GridItem(.adaptive(minimum: 112), spacing: 10, alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AvatarView(member: member)

                VStack(alignment: .leading, spacing: 4) {
                    Text(member.name)
                        .font(.title2.weight(.bold))
                    Text(member.place)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StatusPill(status: member.status)
            }

            DetailRow(title: "Address", value: member.address, systemImage: "mappin.and.ellipse")
            DetailRow(title: "Time at location", value: member.timeAtLocationSummary, systemImage: "timer")
            DetailRow(title: "Time arrived at location", value: member.arrivedAtSummary, systemImage: "arrow.down.circle.fill")

            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 10) {
                MetricPill(systemImage: "iphone", text: member.device)
                MetricPill(systemImage: "battery.75percent", text: "\(member.batteryLevel)%")
                MetricPill(systemImage: "clock.arrow.circlepath", text: member.updatedAt)

                if let speed = member.speed {
                    MetricPill(systemImage: "speedometer", text: speed)
                }

                if let eta = member.eta {
                    MetricPill(systemImage: "clock", text: eta)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct DetailRow: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.weight(.medium))
            }

            Spacer(minLength: 0)
        }
    }
}

private struct AvatarView: View {
    var member: FamilyMember

    var body: some View {
        Text(String(member.name.prefix(1)))
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(member.tint, in: Circle())
    }
}

private struct StatusPill: View {
    var status: MemberStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(status.color.opacity(0.12), in: Capsule())
    }
}

private struct MetricPill: View {
    var systemImage: String
    var text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
    }
}

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DashboardView(
                members: FamilyFixtures.members,
                selectedMember: .constant(FamilyFixtures.members[0]),
                locationSharing: LocationSharingStore(),
                cloudSharing: CloudLocationSharingStore()
            )
        }
    }
}
