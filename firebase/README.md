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
```
node admin.js create-sale ft-oct-2026 "October Yearling Sale" "Fasig-Tipton" "Oct 27, 2026"
node admin.js import-hips ft-oct-2026 hips.csv
```
Every sale appears in the app's sales list, newest first. The sale created last is marked NOW
(`config/app.currentSale`).

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
