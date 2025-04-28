## 📱 Mobile Health MVP
See [`docs/MOBILE_HEALTH_MVP_DESIGN.md`](docs/MOBILE_HEALTH_MVP_DESIGN.md) for
the complete architectural blueprint, component diagram, and rollout plan.

## Local Environment – Post-Install Fixes

### 1. Add Flutter & Dart to your PATH
```bash
echo 'export PATH="$PATH:$HOME/development/flutter/bin"' >> ~/.zshrc   # or ~/.bash_profile
source ~/.zshrc                                                       # reload shell

# Verify
flutter --version
dart --version
```

### 2. Accept Android SDK Licenses
```bash
flutter doctor --android-licenses
# Press `y` to accept each license.
```

Re-run `flutter doctor`; all checks should now pass.

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
