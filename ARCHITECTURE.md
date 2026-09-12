# Whereabouts Architecture

Updated September 12, 2026. This describes the implementation in build 1.0 (11), not a claim of physical-device validation. TestFlight state below was verified on that date and may change.

## Decision

Use Core Location, CloudKit private/shared databases, private CloudKit invitations, and CloudKit push subscriptions. CloudKit is the backend. A separate hosting account is unnecessary for this personal, Apple-only, trusted-family circle. The app requires installation and explicit sharing consent on every phone. It cannot import Find My people locations.

A custom backend would be warranted for Android support, administrative audit trails, or strict per-member write ownership. It would still not bypass iOS background-execution limits.

## Identity and Service Lifetime

- CloudKit verifies the iCloud account on the phone. A chosen display name is a label, not proof of identity.
- Legacy local profiles bind to the verified iCloud identity without unlocking the screen.
- Face ID/device passcode protects viewing the map. Screen locking does not revoke previously enabled background sharing.
- SharingRuntime owns authentication, location, network recovery, and cloud synchronization for the process lifetime. SwiftUI views observe these services.
- An iCloud account change suspends uploads, clears visible locations, and signs out the local profile.

## Invitations and Membership

- One active circle per installation. A joined shared zone takes precedence over an accidentally created owner zone during migration.
- Owner writes use the private database. Joined members use the shared database, with the owner's actual zone ID.
- The owner prepares a saved CKShare before showing UICloudSharingController. This avoids the former empty preparation sheet.
- Invitations use private access to selected Apple accounts, not public read/write bearer links. Owners can manage participants in Apple's sharing sheet.
- AppDelegate, UIWindowSceneDelegate, and SwiftUI URL callbacks receive invitations. Cold-launch metadata and invitations received before sign-in are persisted until the app is unlocked. Repeated callbacks for the same pending link are deduplicated.
- People includes a paste-link recovery path. Only HTTPS iCloud share links are accepted; TestFlight/App Store installation links, lookalike hosts, and metadata for other CloudKit containers are rejected.
- Opening an invitation resolves an owner preview, not automatic acceptance. The explicit Join action revalidates metadata, checks that specific acceptance result, finds the expected shared zone, and successfully reads it before reporting a verified connection.
- Own invitations explain that the recipient must open them on their phone. Repeated acceptance does not create additional circles. Failed joins retain the invitation for retry.
- Metadata lookup, join confirmation, and share preparation have a 25-second UI timeout. Generation checks ignore late results after replacement, cancellation, timeout, or an iCloud account change. Apple's request may still complete server-side; retry can recover an already-accepted share.
- Switching circles requires confirmation and pauses this phone's sharing. Enabling sharing remains a separate, explicit consent action. A canceled join does not undo membership Apple may already have accepted, but it does not enable location publication.
- Membership is displayed separately from location publication. A joined person can have no location because sharing or permission is off.
- Leaving a joined circle deletes its zone from the shared database, removing the participant's access. Deleting an owned zone removes the circle for everyone.
- Existing older public links become private when the owner opens invitation management in this build. Existing participants remain collaborators. The owner must issue private invitations for new members.

## Location Publication

- New installations start with sharing off.
- Collection requires a signed-in profile matching the verified iCloud account, verified access to the active circle, sharing enabled, and iOS authorization. A saved circle identifier alone is not sufficient.
- Always authorization enables background updates, significant-change monitoring, and visit monitoring. The app restarts these services after launch once identity is validated.
- Approximate sharing rounds coordinates before any upload and suppresses street-level reverse geocoding.
- Only the newest unsent fix is retained. Sample timestamps, rather than upload times, indicate freshness.
- Uploads normally occur after 50 meters of movement or 60 seconds since the last successful upload. This is a throttle, not a promised delivery interval.
- Arrival estimates use a fixed local anchor. Slowly moving away from a location does not indefinitely preserve the original arrival time.
- A gap longer than ten minutes resets the arrival estimate. Time at location ends at the last observation; the UI does not invent continued presence.

## Delivery and Recovery

- SharingPersistence stores the active circle, account binding, pending invitation, arrival estimate, latest unsent fix, and removal queue.
- The file uses iOS data protection and is excluded from backups.
- A single upload worker serializes writes. It refetches the record before saving, preserves the sample timestamp, and retries transient errors with backoff and Apple's retry hints.
- Stale queued samples older than five minutes are discarded. A fresh fix is requested on reconnect.
- Pausing clears queued uploads and durably queues removal. A save already in flight is followed by removal if consent ended during that save.
- Every queued fix carries its sharing deadline. Retries recheck that deadline before saving and remove a write that completes after expiration.
- A temporary background execution allowance gives an upload a chance to finish. It does not guarantee runtime or delivery.
- Private and shared database subscriptions trigger refreshes through APNs. Push notifications are hints, not the only source of synchronization.
- Foreground refresh every 15 seconds and network-restoration refresh cover coalesced or missing pushes.
- Zone reads process all pages and deletions before replacing the visible snapshot. Stable record IDs preserve map selection.
- Locations older than three minutes are marked last known. Missing battery information is not displayed as a fabricated 0%.

## Production Configuration

- Bundle ID: com.lancecromwell.Whereabouts
- Team: 92QY292282
- CloudKit container: iCloud.com.lancecromwell.Whereabouts
- Record type: WhereaboutsLocation
- Fields: userRecordName, displayName, latitude, longitude, horizontalAccuracy, address, arrivedAt, updatedAt
- Apple-managed share record type: cloudkit.share
- Required entitlements: CloudKit container/services and APNs
- Required background modes: location, remote-notification, fetch
- CKSharingSupported must remain true.
- TestFlight uses the Production CloudKit environment. Both record types must exist there.
- Production signing profile: Whereabouts App Store Push 20260911
- No new server record fields are introduced in this build.

### App Identity Isolation

The Whereabouts container must be assigned only to Whereabouts in Apple Developer's App ID configuration. Do not use Select All in iCloud Container Assignment. Correct source entitlements alone do not establish that the server-side app associations are isolated.

On September 11, 2026, an invitation naming Cigar Curator prompted an audit. Apple's portal and Cigar Curator's distribution profile both showed the Whereabouts container assigned to that unrelated app. The Whereabouts assignment was removed from Cigar Curator, preserving its two existing cigar-related containers. Reloading both App ID configurations confirmed the separation. A replacement distribution profile, Cigar Curator App Store Isolated 20260911, was generated using the existing distribution certificate and verified to exclude Whereabouts.

Whereabouts' signed 1.0 (10) package already contains only its intended container. No Whereabouts binary change was made for this configuration correction. The cross-assignment is a confirmed configuration defect, but correction of the reported invitation behavior still requires a physical-device retest.

Before release, check the App ID container assignments, provisioning profiles, and signed app entitlements. Include a real invitation test on a phone with the developer's other apps installed, and verify both the invitation's displayed app identity and the app launched by its link.

## Trust and Operating Limits

Zone-wide read/write sharing treats invited members as trusted collaborators. It does not enforce that only a record's named user may modify that record. Do not describe this as a tamper-proof location service.

No iOS application can guarantee continuous updates when the phone is offline, powered off, has revoked permission, or the user has force-quit it. Silent pushes may be delayed. Pausing is immediate locally, but deletion of the prior cloud record can only happen after connectivity returns. Timed sharing is enforced when the process runs; offline receivers retain the last known observation until the cloud deletion arrives.

## Verification

The test target injects LocationCloudTransport rather than bypassing production synchronization through a shared local JSON file. Two test personas exercise the actual outbox and record-mapping code against an in-memory transport. The invitation fixture exposes the shared zone only after acceptance: owner share preparation, recipient preview, explicit Join, zone/read confirmation, and bidirectional publication are exercised without directly activating the recipient's circle. This fake does not reproduce Apple's identity, permissions, routing, or delivery services.

Tests also cover circle routing, identity changes, offline replay, in-flight pause, freshness, approximate coordinates, arrival anchoring, service lifetime across locking, saved invitations after relaunch, wrong accounts/containers, read-only invites, missing shared zones, unreadable records, duplicate callbacks, cancellation, timeouts, and sharing consent on circle changes.

Build 11 verification on September 12, 2026:

- All 36 tests passed on iPhone 16e / iOS 26.2 and iPhone 17e / iOS 26.5 simulators, with normal Xcode test signing.
- Manual simulator UI checks covered the invitation entry sheet, actionable rejection of an installation link, missing-iCloud recovery, a wrapped deep link, persisted recovery after termination/relaunch, and portrait/landscape layouts. These checks used the DEBUG-only local sign-in bypass, not real Apple identities.
- The Release archive and IPA export succeeded. Signature verification passed. Exported entitlements specify only the Whereabouts container, Production CloudKit, production APNs, and get-task-allow=false. The app icon and version 1.0 (11) are present. DEBUG authentication-bypass strings are absent from the Release executable.
- App Store Connect accepted the upload without errors. Subsequent API readback confirmed build 85f74193-dcbc-479b-a661-e79187c8a227 is VALID, beta review is APPROVED, and external status is IN_BETA_TESTING with automatic tester notifications enabled. External QA, the sole existing group, includes build 11. English test notes were saved and read back. This proves beta availability, not installation on a phone.
- No server schema change is required. A fresh command-line production-schema export could not run because this session had no CloudKit management token; this run does not establish new production-schema evidence.

Simulator tests do not prove Apple's account authorization, invitation delivery, production schema, APNs delivery, or physical-device background scheduling.

Before calling the family deployment verified, use two physical iPhones with separate Apple accounts and the same build:

1. Owner invites the recipient's iCloud account. Confirm the real invitation is delivered.
2. Recipient opens it from terminated, locked, and already-open app states. Confirm the owner preview, tap Join, and verify Connected. Opening the owner's own link must display an explanation instead. Repeat using People > Join with invitation as a routing fallback.
3. Enable sharing and Always location on both phones. Confirm each phone sees the other and sees successful Last sent.
4. Lock both phones and move one between two known locations. Compare real fixes and arrival estimates.
5. Interrupt network, reconnect, pause while offline, then reconnect again. Confirm recovery and removal.
6. Revoke a participant, reopen the app, and verify former access is gone.
7. Verify a force-quit or offline phone appears as last known rather than live.

## Apple References

- [Accepting share invitations in SwiftUI](https://developer.apple.com/documentation/coredata/accepting-share-invitations-in-a-swiftui-app)
- [Apple zone-sharing sample](https://github.com/apple/sample-cloudkit-zonesharing)
- [CloudKit database subscriptions](https://developer.apple.com/documentation/cloudkit/ckdatabasesubscription)
- [Background location updates](https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background)
