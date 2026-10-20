# RentLedger

A modern Flutter application for residential and commercial landlords in India to manage properties, track rental income & expenses, handle sub-meter electricity calculations, manage tenant lifecycles, and generate automated settlement statements.

---

## Features

- **Property Management**: Track multiple properties, rental rates, maintenance fees, and occupancy status.
- **Tenant Management**:
  - Full onboarding workflow with security deposit tracking.
  - Edit tenant details (name, phone, email, lease dates, and rate overrides).
  - Multi-step exit wizard with automated settlement calculation (pending dues, deductions, deposit refund).
  - Historical audit trails and past tenant records.
- **Electricity & Utility Tracking**:
  - Sub-meter calculations based on previous/current readings and unit rates.
  - Fixed and direct EB support.
- **Ledger & Transactions**:
  - Rent, advance, maintenance, electricity, repair, and other transaction types.
  - Part-payments and monthly roll-up summaries.
- **Document & Image Storage**:
  - Property photos, tenant ID proofs, and payment receipts stored on Cloudinary.
  - Secure signed deletion support to remove assets permanently when deleted from the app.
- **Reports & Exporting**:
  - Monthly statement PDFs, annual ledger spreadsheets (Excel/CSV), and settlement receipts.

---

## Environment Setup & Configuration

The application uses Cloudinary for storing photos, receipts, and ID proofs.

### 1. The `.env` File
Create a `.env` file in the root directory (see `.env.example`):

```env
CLOUDINARY_CLOUD_NAME=sqfv2g1n
CLOUDINARY_UPLOAD_PRESET=rentledger_unsigned
CLOUDINARY_API_KEY=131132525172676
CLOUDINARY_API_SECRET=8b0mOdf-1ogFGiMRXfVCIJIDb38
```

| Key | Description | Required |
|---|---|---|
| `CLOUDINARY_CLOUD_NAME` | Cloudinary account cloud name | Yes |
| `CLOUDINARY_UPLOAD_PRESET` | Unsigned upload preset for client uploads | Yes |
| `CLOUDINARY_API_KEY` | API Key used for permanent asset deletion | Optional (defaults configured) |
| `CLOUDINARY_API_SECRET` | API Secret used for signing deletion requests | Optional (defaults configured) |

> **Note:** `.env` is ignored by git to protect credentials from being committed to public repositories.

---

## Running the App

### Standard Run
Default credentials are built into the configuration fallback, so you can run:

```bash
flutter run
```

### Run with `.env` File
To explicitly load values from your `.env` file:

```bash
flutter run --dart-define-from-file=.env
```

### Build for Release
When building APKs or App Bundles:

```bash
flutter build apk --release --dart-define-from-file=.env
# or
flutter build appbundle --release --dart-define-from-file=.env
```

---

## IDE Configuration (Optional)

### VS Code
Add the following to `.vscode/launch.json` to automatically load `.env` when pressing **F5**:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "RentLedger",
      "request": "launch",
      "type": "dart",
      "args": ["--dart-define-from-file=.env"]
    }
  ]
}
```

---

## Testing

Run all unit and widget tests:

```bash
flutter test
```
