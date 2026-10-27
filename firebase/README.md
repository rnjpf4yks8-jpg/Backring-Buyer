# HAINTEL on Firebase

Until these steps are done the app runs in demo mode on sample data.

## One-time setup (about 20 minutes)
1. Go to https://console.firebase.google.com and create a project named **HAINTEL**.
2. **Add an iOS app** with bundle id `com.example.haintel` (or your own id; change it in Xcode to match).
   Download `GoogleService-Info.plist` and drop it into the `HAINTEL/` folder next to `HAINTELApp.swift`.
   The app switches from demo data to Firebase automatically.
3. **Authentication** → Sign-in method → turn on **Email/Password**.
4. **Firestore Database** → Create database (production mode).
5. **Storage** → Get started. Storage needs the Blaze (pay as you go) plan; it's cheap at this size.
6. Publish the security rules. Either paste `firestore.rules` and `storage.rules` into the Rules tabs in the
   console, or with the Firebase CLI: `firebase deploy --only firestore:rules,storage`.
   Storage rules read user roles from Firestore; allow that when the console asks.
7. **Project settings → Service accounts → Generate new private key.** Keep that file private.
   Then on a computer with Node.js:
   ```
   cd firebase
   npm install
   export GOOGLE_APPLICATION_CREDENTIALS=/path/to/that-key.json
   ```

## Roles, approvals and the administrator
Everyone signs up as a **buyer**. People who pick **Vet**, **Bloodstock agent** or **Staff** (at sign-up,
or later on the Account screen) send a request; they use the app as a buyer until it's approved.
The **administrator** gets a push notification for each request and approves or declines it on the
**People** screen (the people button at the top of the sales list, or Account → People and requests).
The person gets a push notification with the decision. The administrator can also change anyone's
role (Buyer takes access away) and **delete accounts** (sign-in, profile, purchases and panel spots).

Staff can do everything with sales, hips, grades, panels and opinion approvals; putting a buyer on
a panel still makes them a vet or agent. Only the administrator handles role requests and accounts.

**Administrator tools** (all in the app, no Cloud Function needed):
- **Add a person:** People → Add a person. Name, email and role (buyer, vet, bloodstock agent, staff or
  administrator). Leave the password blank and they get Firebase's password email to choose their own
  (it can land in junk mail; People → the person → Email a link to set their password sends it again).
  The app makes the sign-in on a second copy of Firebase so the administrator stays signed in.
- **Delete a sale:** press and hold it on the sales list → Delete sale (or Edit sale → Delete sale).
  It deletes the hips, vet reports, opinions and their files, then the sale. Purchase records stay
  with the buyers' accounts.
- **Vet reports:** Vet Report button → Edit → Add PDF or image file. With a PDF attached, grades and
  notes are optional. Delete vet report takes the whole report and its files off the hip.
- **Vet and bloodstock opinions:** staff and the administrator can post or edit any slot (Vet 1, Vet 2,
  BS1, BS2): pick it in the menu on the Vet Opinions or Bloodstock Opinions screen, tap Post or Edit,
  attach the PDF, and leave Approve now on so buyers can buy it right away. Delete opinion is on the
  opinion's status card. The security rules already allowed staff to write opinions and their files.

**Becoming the administrator (once):** sign in, open Account, enter the administrator code under
Owner setup and tap Become administrator. This works only while there is no administrator yet; after
that, the administrator can make others administrators on the People screen. Set the code (at least 6
characters, keep it private) with `firebase functions:secrets:set STAFF_CODE`.

**Push notifications** need an Apple push key (.p8) from developer.apple.com → Keys, saved as secrets:
```
firebase functions:secrets:set APNS_KEY --data-file AuthKey_XXXXXXXXXX.p8
firebase functions:secrets:set APNS_KEY_ID
firebase deploy --only functions,firestore:rules,storage
```
The app's App ID also needs the Push Notifications capability, with a refreshed provisioning profile.

## Report files (PDF and photos)
Vets and bloodstock agents can attach their written report, radiographs or scope images to an opinion
(Add photos, Add PDF or image file, or Scan paper report with the camera). Staff can attach the
repository report to a hip's Vet Report. Photos are shrunk to 2400 px JPEGs; files can be up to 20 MB.

Who can open them (`storage.rules`): opinion files, the vet or agent who posted them, staff and the
administrator, and buyers who bought that opinion; vet report files, anyone signed in. The app never
shares download links, so these rules apply every time a file is opened. Deploy rule changes with
`firebase deploy --only storage`. (Until `storage.rules` from October 2026 is deployed, deleting a sale
leaves its uploaded walk videos and sale pictures in Storage; nothing points to them.)

## AI conformation check (sale walk video)
Staff can ask the AI for a C grade from a hip's sale walk video: edit the hip (Hip Number button),
tap **Suggest C grade from walk video**, then **Use** the grade or type your own, and Save. The AI
(Claude) looks at 12 still frames from across the video and returns a grade, its confidence, strengths,
faults and what the video didn't show. Nothing changes until staff tap Save.

The video must be uploaded on the Sale Walk Video button (or be a direct link to a video file).
Vimeo and YouTube page links can't be read. Each check costs roughly 10 cents of AI usage.

One-time setup, from this `firebase` folder with the Firebase CLI (`npm install -g firebase-tools`, then `firebase login`):
1. Get an API key at https://console.anthropic.com (Settings → API keys).
2. `firebase functions:secrets:set ANTHROPIC_API_KEY` and paste the key when asked.
3. `firebase deploy --only functions` (this also deploys the purchase checker).

## For each sale
**In the app (easiest):** staff tap **+** on the sales list to add the sale, open it, then tap
**+ → Import spreadsheet** and pick the catalog saved as CSV (from Files, iCloud Drive or an email).
The app shows how many hips it found and which are new before importing. Column names are matched
loosely (Hip / Hip No, Broodmare Sire, Colour, YOB…), C/F/G and B/Ch/Dk B/Br abbreviations are spelled
out, and re-importing updates catalog details without touching vet reports, opinions or media.

**On a computer** (needs a service account key, which some Google Workspace organizations block):
Staff add the sale in the app: **+** on the sales list, then the sale's name, company and date. Leave
**Feature this sale** on to mark it NOW (`config/app.currentSale`). The sheet shows the sale's ID
(e.g. `ft-oct-2026`); use it to import the catalog. Press and hold a sale to change its name, company
or date later. Or do the same from a computer:
```
node admin.js create-sale ft-oct-2026 "October Yearling Sale" "Fasig-Tipton" "Oct 27, 2026"
node admin.js import-hips ft-oct-2026 hips.csv
```
Every sale appears in the app's sales list, newest first. The sale created or featured last is marked NOW.

`hips.csv` follows `hips-template.csv`: one row per hip with the catalog details from the sale company's
website. Re-importing updates catalog fields only; what staff entered in the app is kept.
Optional columns `pedigreeURL`, `walkVideoURL`, `photoURL` and `walkVideoLength` link each hip's catalog
page, walk video and sale picture on the sale company's site.
Optional columns `conformation_grade` (C, 1–10) and `pedigree_grade` (P, 1–5), in half points like 8.0 or
4.5, are Backring Buyer's grades; `grade_notes` is a one-line reason. A blank cell keeps the hip's current grade, and
a value out of range is skipped with a warning. The app shows the grades beside the hip number and ranks
each hip by them within the sale. Staff can also enter grades in the app (Hip Number → Edit).
Staff can also add and edit hips one at a time in the app (the + button).

## People
Everyone first creates an account in the app (these start as buyers). Then:
```
node admin.js set-role staff.member@haintel.com staff "T. Nguyen"
node admin.js assign ft-oct-2026 vet1 vet.one@example.com "Bluegrass Equine"
node admin.js assign ft-oct-2026 vet2 vet.two@example.com "Hagyard Partners"
node admin.js assign ft-oct-2026 bs1  agent.one@example.com "Whitaker Bloodstock"
node admin.js assign ft-oct-2026 bs2  agent.two@example.com "Castellano Thoroughbreds"
```
Vet 1 and Vet 2 share the **Vet Opinions** button; BS1 and BS2 share **Bloodstock Opinions**. Each screen has a
menu to pick whose opinion to read. Each vet and agent sees a **Post** button on their own group's screen, and it
posts only their own opinion. Staff see **Edit** on every other button.

## Who can see what
- Catalog data (hip info, Backring Buyer grades, pedigree, vet report summary, history, reserve, video, picture, HP): everyone.
- Vet 1, Vet 2 (under Vet Opinions) and BS1, BS2 (under Bloodstock Opinions): the author, staff, and buyers
  who paid ($25 vet, $50 agent). Each opinion is bought on its own.

## Payments
For testing, `node admin.js test-purchases on` lets the Buy button unlock opinions without charging.
Before launch, Apple requires in-app purchase for content like this: set up the products in App Store
Connect, switch the Buy button to StoreKit, have a Cloud Function verify each purchase and write
`users/{uid}/purchases/{sale_hip_slot}`, then run `node admin.js test-purchases off`.
