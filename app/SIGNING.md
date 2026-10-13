# Signing release builds

CI builds are **unsigned** by default, so installing them trips the usual
"unknown developer" warnings. To ship signed builds you supply your own keys —
nobody else can, by design. Here's exactly what to drop in.

## Android

1. Create a keystore once (keep it safe and backed up — losing it means you can
   never update the app under the same identity):

   ```
   keytool -genkey -v -keystore diag-tool-release.jks \
     -keyalg RSA -keysize 2048 -validity 10000 -alias diag-tool
   ```

2. Copy `android/key.properties.example` to `android/key.properties` and fill in
   the paths/passwords. Both the file and `*.jks`/`*.keystore` are gitignored.

3. `flutter build apk --release` now signs with your key. (`android/app/build.gradle.kts`
   reads `key.properties` automatically and falls back to debug signing when it's
   absent, so unsigned CI keeps working.)

### Signing in CI
Add these GitHub repository secrets, then the `android` job can decode the
keystore and write `key.properties` before building:
`ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`,
`ANDROID_KEY_ALIAS`. (The workflow step is commented in `.github/workflows/build.yml`.)

## iOS / macOS

A signed, installable iOS build (`.ipa`) requires an **Apple Developer account**
($99/yr) and can only be produced on a Mac with Xcode:

1. In Xcode, open `ios/Runner.xcworkspace`, select the Runner target →
   Signing & Capabilities → choose your Team (automatic signing).
2. `flutter build ipa` produces a signed archive you can upload to TestFlight /
   the App Store, or export for ad-hoc install.

CI builds iOS **unsigned** (`--no-codesign`) only to prove it compiles; it can't
produce an installable iOS app without your Apple certificate and provisioning
profile, which stay on your account.

macOS is the same story: it runs locally unsigned, and distribution needs a
Developer ID certificate.
