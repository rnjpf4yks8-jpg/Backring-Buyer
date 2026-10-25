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

## For each sale
```
node admin.js create-sale ft-oct-2026 "October Yearling Sale" "Fasig-Tipton" "Oct 27, 2026"
node admin.js import-hips ft-oct-2026 hips.csv
```
Every sale appears in the app's sales list, newest first. The sale created last is marked NOW
(`config/app.currentSale`).

`hips.csv` follows `hips-template.csv`: one row per hip with the catalog details from the sale company's
website. Re-importing updates catalog fields only; what staff entered in the app is kept.
Optional columns `pedigreeURL`, `walkVideoURL`, `photoURL` and `walkVideoLength` link each hip's catalog
page, walk video and sale picture on the sale company's site. For breeding stock sales, optional
`soldAs` (broodmare, weanling, ...) and `coveringSire` columns show on the hip screen.
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
Each vet and agent sees a **Post** button on their own button only. Staff see **Edit** on every other button.

## Who can see what
- Catalog data (hip info, pedigree, vet report summary, history, reserve, video, picture, HP): everyone.
- Vet 1, Vet 2, BS1, BS2: the author, staff, and buyers who paid ($25 vet, $50 agent).

## Payments
For testing, `node admin.js test-purchases on` lets the Buy button unlock opinions without charging.
Before launch, Apple requires in-app purchase for content like this: set up the products in App Store
Connect, switch the Buy button to StoreKit, have a Cloud Function verify each purchase and write
`users/{uid}/purchases/{sale_hip_slot}`, then run `node admin.js test-purchases off`.
