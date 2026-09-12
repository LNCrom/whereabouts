import CloudKit
import Foundation

struct CircleInvitation {
    let url: URL
    let containerID: String
    let scope: CircleScope
    let ownerID: String?
    let ownerName: String
    let isOwner: Bool
    let isAccepted: Bool
    let canWrite: Bool

    init(url: URL, containerID: String = CloudKitTransport.containerID, scope: CircleScope,
         ownerID: String?, ownerName: String, isOwner: Bool = false,
         isAccepted: Bool = false, canWrite: Bool = true) {
        self.url = url
        self.containerID = containerID
        self.scope = scope
        self.ownerID = ownerID
        self.ownerName = ownerName
        self.isOwner = isOwner
        self.isAccepted = isAccepted
        self.canWrite = canWrite
    }

    init(_ metadata: CKShare.Metadata) throws {
        guard let url = metadata.share.url else { throw InvitationError.invalidLink }
        let name = metadata.ownerIdentity.nameComponents.map {
            PersonNameComponentsFormatter.localizedString(from: $0, style: .default)
        } ?? ""
        self.init(url: url, containerID: metadata.containerIdentifier,
                  scope: CircleScope(zoneName: metadata.share.recordID.zoneID.zoneName,
                                     ownerName: metadata.share.recordID.zoneID.ownerName, isOwner: false),
                  ownerID: metadata.ownerIdentity.userRecordID?.recordName,
                  ownerName: name.isEmpty ? "Your family" : name,
                  isOwner: metadata.participantRole == .owner,
                  isAccepted: metadata.participantStatus == .accepted,
                  canWrite: metadata.participantPermission == .readWrite)
    }

    func validate() throws {
        guard containerID == CloudKitTransport.containerID,
              scope.zoneName == "WhereaboutsFamilyCircle" else { throw InvitationError.wrongApp }
    }
}

enum InvitationPhase: Equatable {
    case idle, loading, ready, joining, joined, ownInvite, failed
    var isBusy: Bool { self == .loading || self == .joining }
}

enum InvitationError: LocalizedError {
    case invalidLink, downloadLink, wrongApp, readOnly, unconfirmed, timedOut, changed
    case invalidRecipient, recipientNotFound, selfInvitation

    var errorDescription: String? {
        switch self {
        case .invalidLink: return "This is not an iCloud family invitation. Ask the circle owner to send an invitation from People > Invite family."
        case .downloadLink: return "This link installs Whereabouts; it does not join a circle. Ask the circle owner for the separate iCloud family invitation."
        case .wrongApp: return "This invitation belongs to another app or a different kind of share. Your current circle has not changed."
        case .readOnly: return "This invitation cannot share locations both ways. Ask the owner for an invitation with permission to make changes."
        case .unconfirmed: return "Apple has not confirmed access to the family circle yet. Retry joining; you do not need a new invitation."
        case .timedOut: return "iCloud took too long to respond. Check your connection and retry."
        case .changed: return "The invitation changed while joining. Review it and try again."
        case .invalidRecipient: return "Enter the recipient's Apple Account email address, or phone number including the country code."
        case .recipientNotFound: return "Apple could not match this address to an iCloud account. Ask the recipient for the Apple Account email shown in iPhone Settings."
        case .selfInvitation: return "This is your own Apple Account. Enter the family member's Apple Account instead."
        }
    }
}

enum InvitationLink {
    static let entryPage = URL(string: "https://lncrom.github.io/whereabouts/join/")!

    static func entryURL(for shareURL: URL) throws -> URL {
        let shareURL = try validate(shareURL)
        var payload = URLComponents()
        payload.queryItems = [.init(name: "invite", value: shareURL.absoluteString)]
        var entry = URLComponents(url: entryPage, resolvingAgainstBaseURL: false)!
        // Keep the private invitation out of web-server requests and access logs.
        entry.percentEncodedFragment = payload.percentEncodedQuery
        return entry.url!
    }

    static func parse(_ text: String) throws -> URL {
        guard text.utf8.count <= 8192 else { throw InvitationError.invalidLink }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let wrapper = URLComponents(string: trimmed), wrapper.scheme?.lowercased() == "whereabouts" {
            guard wrapper.host == "join",
                  let link = wrapper.queryItems?.first(where: { $0.name == "invite" })?.value else {
                throw InvitationError.invalidLink
            }
            return try validate(URL(string: link))
        }
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let links = detector.matches(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)).compactMap(\.url)
        if let entry = links.first(where: { $0.host?.lowercased() == entryPage.host && $0.path == entryPage.path }),
           let fragment = URLComponents(url: entry, resolvingAgainstBaseURL: false)?.percentEncodedFragment {
            guard entry.scheme == "https", entry.user == nil, entry.password == nil, entry.port == nil,
                  entry.query == nil else { throw InvitationError.invalidLink }
            var payload = URLComponents()
            payload.percentEncodedQuery = fragment
            guard let items = payload.queryItems, items.count == 1, items[0].name == "invite" else { throw InvitationError.invalidLink }
            return try validate(items[0].value.flatMap(URL.init(string:)))
        }
        if let link = links.first(where: { ["icloud.com", "www.icloud.com"].contains($0.host?.lowercased() ?? "") }) {
            return try validate(link)
        }
        return try validate(links.first ?? URL(string: trimmed))
    }

    private static func validate(_ url: URL?) throws -> URL {
        guard let url, let host = url.host?.lowercased() else { throw InvitationError.invalidLink }
        if ["testflight.apple.com", "apps.apple.com", "itunes.apple.com"].contains(host) { throw InvitationError.downloadLink }
        guard url.scheme?.lowercased() == "https", ["icloud.com", "www.icloud.com"].contains(host),
              url.user == nil, url.password == nil, url.port == nil,
              url.pathComponents.count == 3, url.pathComponents[1] == "share",
              !url.pathComponents[2].isEmpty else { throw InvitationError.invalidLink }
        return url
    }
}

enum InvitationRecipient: Equatable {
    case email(String), phone(String)

    init(_ text: String) throws {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= 254, !value.isEmpty else { throw InvitationError.invalidRecipient }
        if value.contains("@") {
            let parts = value.split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
                  value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { throw InvitationError.invalidRecipient }
            self = .email(value)
        } else {
            let number = value.filter { !" ()-.".contains($0) }
            guard number.first == "+", (8...15).contains(number.dropFirst().count),
                  number.dropFirst().allSatisfy({ "0123456789".contains($0) }) else { throw InvitationError.invalidRecipient }
            self = .phone(number)
        }
    }
}
