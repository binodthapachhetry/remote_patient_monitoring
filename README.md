# Remote Patient Monitoring — 🔗 EHR Data Enrichment Module
_A production-ready Flutter reference app that captures patient-generated health data via Bluetooth LE devices and posts FHIR/HL7-compliant messages to any modern EHR platform._

![platform](https://img.shields.io/badge/platform-ios%20%7C%20android%20%7C%20macos-green)
![build](https://github.com/<org>/<repo>/actions/workflows/ci.yml/badge.svg)
![license](https://img.shields.io/github/license/<org>/<repo>)

## 🤝 At a Glance — Why EHR Vendors Care
* Drop-in module that **enriches existing EHRs with real-time, patient-generated data** (weight, BP, glucose, …) without changing the EHR’s core schemas.  
* Outputs **standards-compliant HL7 V2 / FHIR bundles**; your integration layer consumes them exactly as any other lab feed.  
* Designed for **HIPAA-grade security** — on-device AES-256 encryption, rotated keys, and background data purge.  
* Ships with a reference Android foreground service and iOS background modes for uninterrupted BLE connectivity.

## 🚀 Key Capabilities
- Bluetooth LE device discovery, auto-reconnect & background data capture  
- Local SQLite persistence with resumable batching  
- Secure HL7/FHIR serialization with pluggable cryptographic key rotation  
- Connectivity-aware sync & dead-letter-queue retry handling  
- Firebase Auth + e-mail approval gate for quick PoC demos  

See the full design doc in [`docs/MOBILE_HEALTH_MVP_DESIGN.md`](docs/MOBILE_HEALTH_MVP_DESIGN.md).

## 🏗 Architecture Snapshot
```text
 BLE Device ─┐               ┌──────────┐     HL7/FHIR     ┌────────┐
             │               │          │  HTTPS/WebSocket │        │
┌────────────▼──────┐   ┌────▼────┐     │                  │  EHR / │
│ DeviceDiscoverySvc │──► DB (Batch) ├──► SyncService ─────►  HIS   │
└────────────────────┘   └──────────┘                        └────────┘
```

### Quick Start (for decision-makers)
```bash
git clone <repo_url> && cd mobile_app
flutter run -d macos   # 60-second demo on desktop
```

---

## 👩‍💻 Developer Setup  <!-- rename the existing env section -->
See [`docs/MOBILE_HEALTH_MVP_DESIGN.md`](docs/MOBILE_HEALTH_MVP_DESIGN.md) for
the complete architectural blueprint, component diagram, and rollout plan.

## Running the App

1. List available devices/emulators  
```bash
flutter devices          # shows IDs such as macos, chrome, 48241FDAQ00584
```

2. (Optional) Start an Android emulator  
```bash
flutter emulators                     # list emulators
flutter emulators --launch pixel_9    # use the exact emulator ID
```

3. Run on a specific target **instead of** `any`  
```bash
# Desktop
flutter run -d macos

# launch the real app
cd mobile_app
flutter run -d 48241FDAQ00584

# Chrome web
flutter run -d chrome
```

`any` works only when at least one **supported** device is already booted/connected;  
explicit IDs eliminate the ambiguity and avoid the “No supported devices” error.

## 🛠️ First-Time Project Bootstrap

After cloning, the repo contains only Dart sources and `pubspec.yaml`.  
Generate the native platform folders once with:

```bash
cd mobile_app
# Include every platform you need; omit the rest.
flutter create . --platforms=android,ios,macos,web
```

The command is idempotent and will not overwrite existing Dart code.  
Then run the app:

```bash
flutter run -d <device_id>   # e.g. flutter run -d 48241FDAQ00584
```

### 🔄  Sync Dart/Flutter Dependencies

Whenever `mobile_app/pubspec.yaml` changes (e.g., we added
`permission_handler`), fetch the packages before building:

```bash
cd mobile_app
flutter pub get        # downloads permission_handler and all transitive deps
```

If the IDE still shows “package … not found,” restart the IDE or run
`flutter clean && flutter pub get`.

This removes the “AndroidManifest.xml could not be found” error.

## 🔍 How to Evaluate Each Commit

Every pull-request or commit created with the three-phase convention includes
a **PHASE 3 – REVIEW INTERFACE** block.  
Follow the checklist therein:

1. Unit / widget / integration test commands  
2. Static-analysis commands (`flutter analyze`, `dart test`, etc.)  
3. Manual verification steps (e.g., `flutter run -d macos`)  

For convenience, copy any shell snippets exactly as shown; they are
guaranteed to work on macOS / Linux with the tool-versions pinned in
`README.md`.
