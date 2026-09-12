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
3. One person chooses People > Invite family. Enter the recipient's Apple Account email or international phone number, or choose that detail from Contacts. Prepare and send the invitation through Messages or another sharing option. If Apple cannot match the account, ask for the Apple Account email shown in that person's iPhone Settings.
4. Each recipient opens the Whereabouts invitation page and taps Open in Whereabouts. Unlock the app, review who sent the invitation, and tap Join family circle. Check that Connection says Connected. Joining does not turn on location sharing.
5. Each person turns on Share my location and approves location access. Choose Always in iPhone Settings for sharing while the app is in the background.

The sender opening their own invitation does not add another person. A person who has already joined should not create another circle.

The TestFlight link installs the app only. It does not connect two phones. If an iCloud invitation only opens the app or Apple's routing fails, copy that iCloud invitation link and use People > Join with invitation > Review invitation. The app retains valid invitations through sign-in and relaunch. Replacing or dismissing an invitation cancels the prior local attempt.

### Invitation Opens Cigar Curator

Apple's download metadata for a Whereabouts iCloud invitation was confirmed to name Cigar Curator, despite corrected App ID assignments. Build 12 sends a Whereabouts-specific entry-page link that avoids that lookup. Update the sender to build 12 and send through Invite family. The receiver's Open action works with build 11 or later; updating both phones is recommended.

Previously sent raw iCloud links are not rewritten. Do not install Cigar Curator to join Whereabouts, and do not delete your circle. Use the in-app paste option for an old link. Manage members is for reviewing or revoking participation; send new invitations through Invite family to get the Whereabouts-specific link.

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
