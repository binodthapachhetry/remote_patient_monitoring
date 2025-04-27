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
