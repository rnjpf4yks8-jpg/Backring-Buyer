# HAINTEL (iOS)

SwiftUI app for reviewing a sale hip. The home screen shows the current hip, with HAINTEL's
conformation and pedigree grades (C · P) and their ranks in the sale beside the hip number, and 10 buttons
that fit on one iPhone Pro screen. Each button pushes its own screen; Back returns home, and
the bar at the bottom of each screen steps to the previous or next button. The arrows in the
header step through hips in catalog order.

## Open and run
1. Copy the `haintel` folder to a Mac with Xcode 16 or later.
2. Open `HAINTEL.xcodeproj`, pick an iPhone 16 Pro simulator, press Run.
3. To run on a phone, set your Team under Signing & Capabilities and change the bundle id
   (`com.example.haintel`).

Requires iOS 17. Files are picked up automatically from the `HAINTEL/` folder.

## Where things live
- `Models.swift` – Hip data model and the 10 buttons (`HipField`).
- `Store.swift` – `SaleStore`: app state, permissions, grade ranks and button summaries.
- `SampleData.swift` – placeholder hips. Replace with a real feed.
- `Theme.swift` – Eliskopes colors (navy #0B1730, amber #F2B544) and shared components.
- `Views/SaleView.swift` – hip header and the 2×5 button grid.
- `Views/FieldScreen.swift` – pushed screen with previous/next bar.
- `Views/FieldContent.swift` – content for each of the 10 buttons.

## Data and sign-in
The app uses Firebase once `GoogleService-Info.plist` is in the `HAINTEL/` folder; until then it runs on
sample data (demo mode), where the account button lets you switch between a buyer, staff, two vets and
two bloodstock agents. Setup steps, security rules, the hips spreadsheet template and the admin script
are in `firebase/`.

- **Buyers** browse everything and buy Vet 1, Vet 2, BS1 and BS2.
- **HAINTEL staff** add hips (+) and edit hip info and grades, pedigree, vet report, history, reserve, HP,
  sale picture and walk video (uploaded from the phone).
- **Vets and bloodstock agents** each post and edit only their own opinion.

## Paid opinions
Vet 1 and Vet 2 are under the Vet Opinions button, BS1 and BS2 under Bloodstock Opinions; a menu at the
top of each screen picks whose opinion to read. Each one is locked until bought. The Buy button records a test
purchase without charging (see `firebase/README.md`). Charging for real needs App Store In-App
Purchase (StoreKit) and a Cloud Function that verifies each purchase. Prices: $25 per vet opinion, $50 per bloodstock agent opinion.

HP is the horse physical: height (shown in hands) and length, measured by HAINTEL staff.

Fonts use the system font. To match the website exactly, add IBM Plex Sans/Mono to the
target and change `Theme.sans`/`Theme.mono`.
