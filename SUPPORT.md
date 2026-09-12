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
4. Each recipient opens the iCloud invitation, unlocks Whereabouts, reviews who sent it, and taps Join family circle. Check that Connection says Connected. Joining does not turn on location sharing.
5. Each person turns on Share my location and approves location access. Choose Always in iPhone Settings for sharing while the app is in the background.

The sender opening their own invitation does not add another person. A person who has already joined should not create another circle.

The TestFlight link installs the app only. It does not connect two phones. If an iCloud invitation only opens the app or Apple's routing fails, copy that iCloud invitation link and use People > Join with invitation > Review invitation. The app retains valid invitations through sign-in and relaunch. Replacing or dismissing an invitation cancels the prior local attempt.

## Status and Recovery

- Invitation not accepted yet means Apple has not recorded acceptance. Joined; no location received means membership exists, but a location has not arrived from that phone. These are separate from this phone's Connection status.
- Connected confirms the active circle was successfully accessed, not that every member is reporting. Last circle check, Last sent, and the version number are available in People.
- Invitations that time out can be checked again. A wrong-account error means the owner must invite the Apple Account used in the recipient's iCloud Settings. A revoked invitation needs a new invitation from the owner.
- Last sent shows a successful upload from this phone. Last known location means the other phone has not provided a recent fix.
- Offline uploads retry when the app can run and connectivity returns. Very old pending fixes are discarded.
- Pausing, signing out, or revoking location access stops new sharing. If offline, removal of the previous cloud location waits for connectivity.
- iOS can delay background activity. Force-quitting the app can stop updates until it is reopened. Face ID locks the map without turning off sharing you enabled.
- Arrival and time-at-location are estimates based on observed fixes. They cannot establish uninterrupted presence when the phone has not reported.

[TestFlight](https://testflight.apple.com/join/dJhEQf75)
