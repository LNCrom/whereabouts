# Whereabouts Real-World Architecture

Whereabouts uses Apple-native consent and storage primitives for the production family-location flow.

## What Works

- Each user signs in locally to Whereabouts and revalidates access with device authentication.
- The circle owner creates a private CloudKit custom zone named `WhereaboutsFamilyCircle`.
- The owner shares that whole zone with `CKShare(recordZoneID:)`, using Apple's native `UICloudSharingController`.
- Invited people must install/open Whereabouts, accept the iCloud share, and grant iOS location permission before their phone publishes location.
- Each approved participant writes one `WhereaboutsLocation` record in the shared zone.
- Other approved participants read the shared zone and render live map markers plus:
  - Address
  - Time at location
  - Time arrived at location

## Why This Architecture

Apple does not provide a public API for third-party apps to read Find My people locations. The free native solution Apple does allow is:

- Core Location for each member's own device location.
- CloudKit private/shared databases for consented data sharing.
- CloudKit Sharing for Apple-managed invitations, participant approval, and access control.

Zone-wide CloudKit Sharing is used instead of a single shared root record because location records are continuously created and updated by multiple participants. Sharing the zone makes every approved participant's current location record part of the same consented circle.

## CloudKit Container

The app expects this container:

```text
iCloud.com.lancecromwell.Whereabouts
```

The Apple Developer App ID for `com.lancecromwell.Whereabouts` must enable:

- iCloud
- CloudKit
- Container `iCloud.com.lancecromwell.Whereabouts`
- Background location capability

## CloudKit Schema

The app will create development records as it runs. Before App Store production use, deploy the CloudKit development schema to production in CloudKit Console.

Record type: `WhereaboutsLocation`

Fields:

- `userRecordName`: String
- `displayName`: String
- `latitude`: Double
- `longitude`: Double
- `horizontalAccuracy`: Double
- `address`: String
- `arrivedAt`: Date/Time
- `updatedAt`: Date/Time

System share records are managed by CloudKit as `cloudkit.share`.

## Runtime Behavior

- The app publishes the current device location when sharing is enabled and permission allows it.
- Location writes are throttled: first publish, then meaningful movement or a one-minute refresh interval.
- Address is resolved with reverse geocoding; if geocoding is unavailable, coordinates are stored.
- Arrival time is preserved while the device remains within 100 meters of the previous stored location.
- The foreground app refreshes shared locations every 15 seconds and after successful location publishes.

## Limits

- Whereabouts cannot read Find My data.
- A family member cannot share location without installing/opening Whereabouts and approving iOS location permission.
- Real iCloud share acceptance must be tested on physical devices signed into separate iCloud accounts; generic simulators cannot fully exercise Apple iCloud sharing.
- App Store privacy labels must disclose location data collection and iCloud-backed sharing.
