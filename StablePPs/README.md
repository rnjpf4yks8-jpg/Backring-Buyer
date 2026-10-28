# Stable PPs (iOS)

Your horses' past performances laid out like the Daily Racing Form, and the best upcoming races for
each horse within 200 miles of the track where it last ran.

- **Horses**: add, edit and delete. "Add my 33 horses" fills a new stable from the Equibase Virtual Stable list.
- **Past performances**: from Equibase charts. Open the horse on Equibase (Safari, where you're signed in),
  open a race's chart, then either copy the text and tap **Paste chart**, or tap Safari's Share button and pick
  **Stable PPs**. Saved chart PDFs work too (**Chart PDFs**), and lines can be added or corrected by hand.
  Claude reads each chart (Cloud Function `readChart`) and fills in the horse's breeding, trainer and owner.
- **Best races**: from the condition books you add (track's condition book PDF → **Condition books**). Each
  race is checked for eligibility (age, sex, state-bred, maiden and non-winners conditions, starter
  allowances) and scored on class, distance, surface, days since the last race and travel.

The app never reads Equibase itself; you bring each chart in.

## Where things live
- `StablePPs/Core/`: models, DRF formatting, record boxes, race matching, Equibase links, the 33-horse list.
  No UI or Firebase, so `Tests/CoreCheck.swift` checks it anywhere against `Tests/fixtures.json`
  (results from the web version of Stable PPs). GitHub Actions runs it and builds the app on every push.
- `StablePPs/Backend/StableBackend.swift`: Firebase sign-in, Firestore and the Cloud Function calls.
- `StablePPs/StableStore.swift`: app state and actions.
- `StablePPs/Views/`: screens.
- `../firebase/functions/stable.js`: `readChart` and `readConditionBook` (Claude).

## Data
Same Firebase project and accounts as Backring Buyer (`haintel-f481c`); sign in with the same email and password.
- `stables/{uid}/horses/{horseId}`, `…/races/{lineId}`, `stables/{uid}/books/{bookId}`; only you can read or
  write your own stable (`../firebase/firestore.rules`).
- Reading charts and condition books calls Claude with the `ANTHROPIC_API_KEY` secret Backring Buyer already
  uses, so it's limited to the Backring Buyer administrator and staff accounts.

## One-time setup
1. **Firebase** (from a computer with the Firebase CLI, in `firebase/`):
   `firebase deploy --only functions,firestore:rules`
   This adds `readChart`, `readConditionBook` and the `stables` rule. Until then the app can't save horses.
2. **Apple Developer** (https://developer.apple.com/account):
   - Identifiers → + → App IDs → App → Bundle ID `com.example.stablepps` (no capabilities needed).
   - Profiles → + → App Store → pick `com.example.stablepps` and the "HAINTEL" distribution certificate.
     Name it **Stable PPs** and download it.
3. **App Store Connect** (https://appstoreconnect.apple.com) → Apps → + → New App: name Stable PPs (if the
   name is taken, e.g. "Stable PPs – SEDG"; the home-screen name stays Stable PPs), bundle ID
   `com.example.stablepps`, SKU STABLEPPS001. Add yourself under TestFlight → Internal Testing.
4. **Codemagic**: Team settings → Code signing identities → iOS provisioning profiles → upload the
   **Stable PPs** profile. Then on the Backring Buyer app start a build of the workflow
   **Stable PPs → TestFlight** on `main`. The App Store Connect key "HAINTEL ASC" already covers this app.

### Firebase app registration (optional)
The app ships with Backring Buyer's Firebase config with its bundle ID changed, which works for sign-in and
Firestore. To register it properly: Firebase console → Project settings → Add app → iOS → bundle ID
`com.example.stablepps`, download `GoogleService-Info.plist`, and either replace
`StablePPs/GoogleService-Info.plist` or add it base64-encoded as the Codemagic secure variable
`STABLEPPS_GOOGLE_SERVICE_INFO_PLIST`. Do this if sign-in ever says requests from this app are blocked.

## Open and run
Open `StablePPs/StablePPs.xcodeproj` in Xcode 16 or later, pick an iPhone simulator, press Run. Requires iOS 17.
