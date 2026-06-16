import Foundation
import CoreLocation
import SwiftUI

enum MemberStatus: String, CaseIterable, Identifiable {
    case live = "Live"
    case driving = "Driving"
    case stationary = "Stationary"
    case invited = "Invited"
    case offline = "Offline"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .live: .green
        case .driving: .blue
        case .stationary: .orange
        case .invited: .purple
        case .offline: .secondary
        }
    }
}

struct FamilyMember: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var phoneNumber: String?
    var emailAddress: String?
    var device: String
    var status: MemberStatus
    var place: String
    var address: String
    var batteryLevel: Int
    var updatedAt: String
    var arrivedAt: Date
    var lastLocationUpdate: Date
    var isLocationShared: Bool
    var tint: Color
    var latitude: Double
    var longitude: Double
    var speed: String?
    var eta: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var arrivedAtSummary: String {
        guard isLocationShared else { return "Not sharing yet" }
        return arrivedAt.formatted(date: .omitted, time: .shortened)
    }

    var timeAtLocationSummary: String {
        guard isLocationShared else { return "Not sharing yet" }

        let components = Calendar.current.dateComponents([.hour, .minute], from: arrivedAt, to: Date())
        let hours = components.hour ?? 0
        let minutes = components.minute ?? 0

        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        }

        return "\(max(minutes, 1)) min"
    }
}

enum FamilyFixtures {
    static let members = [
        FamilyMember(
            name: "Ava",
            phoneNumber: nil,
            emailAddress: nil,
            device: "iPhone 15",
            status: .driving,
            place: "Near Westlake High",
            address: "4100 Westbank Dr, Austin, TX",
            batteryLevel: 74,
            updatedAt: "Live",
            arrivedAt: Date().addingTimeInterval(-18 * 60),
            lastLocationUpdate: Date().addingTimeInterval(-30),
            isLocationShared: true,
            tint: .blue,
            latitude: 30.2747,
            longitude: -97.8195,
            speed: "31 mph",
            eta: "Home in 12 min"
        ),
        FamilyMember(
            name: "Marco",
            phoneNumber: nil,
            emailAddress: nil,
            device: "Pixel 9",
            status: .live,
            place: "Home",
            address: "Barton Hills, Austin, TX",
            batteryLevel: 92,
            updatedAt: "1 min ago",
            arrivedAt: Date().addingTimeInterval(-2 * 60 * 60 - 14 * 60),
            lastLocationUpdate: Date().addingTimeInterval(-60),
            isLocationShared: true,
            tint: .green,
            latitude: 30.2554,
            longitude: -97.7797,
            speed: nil,
            eta: "At home"
        ),
        FamilyMember(
            name: "Jules",
            phoneNumber: nil,
            emailAddress: nil,
            device: "Apple Watch",
            status: .stationary,
            place: "Soccer Fields",
            address: "Zilker Park, Austin, TX",
            batteryLevel: 48,
            updatedAt: "6 min ago",
            arrivedAt: Date().addingTimeInterval(-52 * 60),
            lastLocationUpdate: Date().addingTimeInterval(-6 * 60),
            isLocationShared: true,
            tint: .orange,
            latitude: 30.2669,
            longitude: -97.7729,
            speed: nil,
            eta: "Practice until 6:30"
        ),
        FamilyMember(
            name: "Nina",
            phoneNumber: nil,
            emailAddress: nil,
            device: "iPad mini",
            status: .offline,
            place: "Last seen: Library",
            address: "Austin Central Library, Austin, TX",
            batteryLevel: 12,
            updatedAt: "42 min ago",
            arrivedAt: Date().addingTimeInterval(-3 * 60 * 60 - 7 * 60),
            lastLocationUpdate: Date().addingTimeInterval(-42 * 60),
            isLocationShared: true,
            tint: .purple,
            latitude: 30.2653,
            longitude: -97.7517,
            speed: nil,
            eta: nil
        )
    ]

}
