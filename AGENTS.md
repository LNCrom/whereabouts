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
- The current app is mock-data backed; real location sharing still needs Core Location, identity/invites, a backend, push notifications, and geofence persistence.
