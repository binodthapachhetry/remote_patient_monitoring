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

# Physical Android phone
flutter run -d 48241FDAQ00584

# Chrome web
flutter run -d chrome
```

`any` works only when at least one **supported** device is already booted/connected;  
explicit IDs eliminate the ambiguity and avoid the “No supported devices” error.
