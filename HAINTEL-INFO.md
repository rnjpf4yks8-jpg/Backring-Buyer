# Backring Buyer: where everything is

## The app
- App name: Backring Buyer (iPhone, iOS 17+). Shown on the home screen; the Xcode project, folders and bundle ID keep the HAINTEL name
- Bundle ID: com.example.haintel
- Apple team ID (App ID prefix): 8P44VXJJ7X
- App Store Connect SKU: HAINTEL001
- Prices: Vet 1 / Vet 2 opinions $25 each, BS1 / BS2 bloodstock agent opinions $50 each

## Code
- GitHub repo (private): https://github.com/rnjpf4yks8-jpg/Backring-Buyer  (branch: main)
- Every push to main runs a compile check on GitHub's cloud Mac (Actions tab)
- Clickable preview (no Xcode needed): https://claude.ai/artifact/QomEpB4zZqJXexDnK7AJS8

## Building and installing on iPhone
- Codemagic (cloud Mac build): https://codemagic.io, workflow "HAINTEL → TestFlight" (from codemagic.yaml)
  - App Store Connect key in Codemagic is named "HAINTEL ASC"
  - Signing: certificate "HAINTEL" (Apple Distribution) and provisioning profile "HAINTEL" (app_store, com.example.haintel)
- App Store Connect: https://appstoreconnect.apple.com → HAINTEL → TestFlight
- Apple Developer (certificates and profiles): https://developer.apple.com/account/resources

## Data (Firebase)
- Firebase project: haintel-f481c → https://console.firebase.google.com/project/haintel-f481c
- Config file: HAINTEL/GoogleService-Info.plist (already in the repo)
- Setup steps, security rules, spreadsheet template and admin script: firebase/README.md
  - Load a sale:  node admin.js create-sale <id> "<name>" "<company>" "<date>"
                  node admin.js import-hips <id> hips.csv
  - Give people roles: node admin.js set-role / assign  (see firebase/README.md)

## Who does what in the app
- Buyers: browse hips, buy vet and bloodstock opinions
- HAINTEL staff: add and edit hips, C/P grades, vet report, pedigree, reserve, HP (height/length), photo, walk video
- 2 vets (Vet 1, Vet 2) and 2 bloodstock agents (BS1, BS2): each posts only their own opinion
  (in the app they're grouped under the Vet Opinions and Bloodstock Opinions buttons)

## Keep private (never commit or share)
- Apple .p8 API key file
- Firebase service account key (.json) used by admin.js
