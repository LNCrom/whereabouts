# Whereabouts Support

Thanks for using Whereabouts.

Whereabouts is a personal family location dashboard for organizing trusted people, viewing shared locations on a map, and checking location details such as address, time at location, and arrival time when data is available.

## Support Contact

Email: lance.n.cromwell@gmail.com

Phone for App Review contact: +1 425 591 9555

## Important Notes

Whereabouts does not access Apple Find My people-location data. For no-download native iOS location sharing, use Apple's Find My app directly.

Whereabouts stores consented location updates in Apple's CloudKit service. Every family member needs Whereabouts installed and must join the same circle using their own iCloud account.

## Connecting Your Family

1. Update every phone to the same current TestFlight build.
2. Continue with iCloud and choose a display name on each phone.
3. One person creates the family circle from People, then selects the family members in Apple's invitation sheet. Send invitations to the Apple accounts those phones use for iCloud.
4. Each recipient opens the invitation, unlocks Whereabouts, and checks for the joined-circle confirmation.
5. Each person turns on Share my location and approves location access. Choose Always in iPhone Settings for sharing while the app is in the background.

The sender opening their own invitation does not add another person. A person who has already joined should not create another circle.

## Status and Recovery

- Invitation pending means Apple has not recorded acceptance. Joined means membership exists, even if that phone has not shared a location yet.
- Last sent shows a successful upload from this phone. Last known location means the other phone has not provided a recent fix.
- Offline uploads retry when the app can run and connectivity returns. Very old pending fixes are discarded.
- Pausing, signing out, or revoking location access stops new sharing. If offline, removal of the previous cloud location waits for connectivity.
- iOS can delay background activity. Force-quitting the app can stop updates until it is reopened. Face ID locks the map without turning off sharing you enabled.
- Arrival and time-at-location are estimates based on observed fixes. They cannot establish uninterrupted presence when the phone has not reported.

[TestFlight](https://testflight.apple.com/join/dJhEQf75)
