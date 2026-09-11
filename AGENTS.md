# Family Tracker

## Project Context

- This repository is the Family Tracker iOS app.
- Treat `/Users/lancecromwell/Documents/Family Tracker` as the project root.
- The app target is `FamilyLocator` in `FamilyLocator.xcodeproj`.
- The product is a SwiftUI family device location tracker, similar in spirit to Find My and Life360.

## Build

- Build the iOS app with:

  ```sh
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project FamilyLocator.xcodeproj -scheme FamilyLocator -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/family-tracker-derived CODE_SIGNING_ALLOWED=NO build
  ```

## Implementation Notes

- Prefer SwiftUI-native state and small focused views.
- Keep privacy, consent, and member-controlled sharing central to feature decisions.
- Runtime sharing uses Core Location and CloudKit private/shared databases. SharingRuntime owns services for the process lifetime; views must not own or drive background uploads.
- Keep CloudKit network access behind LocationCloudTransport. Unit tests inject a fake transport and do not prove real iCloud invitations or physical-device background delivery.
- Run simulator tests with normal Xcode signing. Disabling signing removes the CloudKit entitlements and can crash the test host at startup.
