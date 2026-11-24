# Release Process

## Publishing a New Version

The helper script `scripts/release/prepare.py` assists with the release preparation:
- `notes`: drafts release notes from git commits since the last tag.
- `bump <version>`: updates version numbers in `pubspec.yaml` and `lib/version.dart`, and moves `[Unreleased]` changes under the new version in `CHANGELOG.md`.
- `check`: validates version numbers, changelog entries, and tag alignment prior to tagging.

Manual release steps:

1. Update `version` in `pubspec.yaml` and `appVersion` in `lib/version.dart` (`test/version_test.dart` ensures they match).
2. Move unreleased changes in `CHANGELOG.md` under the new version heading `## [<version>] - YYYY-MM-DD`.
3. Commit, tag, and push:

   ```sh
   git commit -am "chore(release): bump version to 3.0.x"
   git tag v3.0.x
   git push origin main v3.0.x
   ```

4. The GitHub Actions **Release** workflow builds installation packages for all three platforms and drafts a GitHub Release. Inspect the built packages, then click **Publish release** on GitHub. Applications check for updates against `releases/latest/download/appcast-*.xml`.

   > **Legacy Notice**: The files `latest.yml`, `latest-mac.yml`, and `latest-linux.yml` are generated for legacy 0.4.x (Electron) clients to prompt users to download the Flutter rewrite. Do not delete them.

---

## Configuring Secrets and Variables

Configure these in the repository under **Settings → Secrets and variables → Actions**. If omitted, builds will still generate unsigned platform binaries without automatic update capabilities.

### macOS Code Signing and Notarization

| Name | Type | Description |
| --- | --- | --- |
| `MACOS_CERTIFICATE_P12` | Secret | Developer ID Application certificate and private key exported as `.p12`, encoded with `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PASSWORD` | Secret | Password protecting the `.p12` export |
| `MACOS_SIGNING_IDENTITY` | Variable | Full identity string, e.g. `Developer ID Application: Your Name (ABCDE12345)` (inspect via `security find-identity -v -p codesigning`) |
| `APPLE_API_KEY_P8` | Secret | App Store Connect API Key (`.p8` file) in base64 |
| `APPLE_API_KEY_ID` | Secret | Key ID of the App Store Connect API key |
| `APPLE_API_ISSUER_ID` | Secret | Issuer ID from App Store Connect |

#### Obtaining Apple Credentials

1. **Developer ID Certificate**: In Xcode → Settings → Accounts → Manage Certificates, click `+` and select **Developer ID Application** (requires Account Holder or Admin role). Export the certificate with its private key from **Keychain Access** as `.p12`.
2. **App Store Connect API Key**: Navigate to [App Store Connect](https://appstoreconnect.apple.com/access/integrations/api) → Users and Access → Integrations → App Store Connect API. Create a key with **Developer** permissions, download the `.p8` file (one-time download), and note the Key ID and Issuer ID.

---

### Autoupdate Signing Keys

Sparkle / WinSparkle update packages use dedicated cryptographic keys separate from Apple developer certificates. **Back up private keys securely; if lost, existing installations cannot receive automatic updates.**

| Name | Type | Description |
| --- | --- | --- |
| `SPARKLE_PUBLIC_KEY` | Variable | macOS (Sparkle) EdDSA public key |
| `SPARKLE_PRIVATE_KEY` | Secret | macOS (Sparkle) EdDSA private key |
| `WINDOWS_DSA_PUBLIC_KEY` | Variable | Windows (WinSparkle) DSA public key (full PEM string) |
| `WINDOWS_DSA_PRIVATE_KEY` | Secret | Windows (WinSparkle) DSA private key (full PEM string) |

#### Generating Autoupdate Keys

```sh
# macOS Sparkle: Build once to allow CocoaPods to install Sparkle
flutter build macos
macos/Pods/Sparkle/bin/generate_keys                          # Prints public key → SPARKLE_PUBLIC_KEY
macos/Pods/Sparkle/bin/generate_keys -x sparkle_private.key # File content → SPARKLE_PRIVATE_KEY

# Windows WinSparkle DSA keys:
openssl dsaparam -genkey 2048 -out dsa_priv.pem              # File content → WINDOWS_DSA_PRIVATE_KEY
openssl dsa -in dsa_priv.pem -pubout -out dsa_pub.pem        # File content → WINDOWS_DSA_PUBLIC_KEY
```

When configured, release builds include `--dart-define=YPM_SPARKLE=true`. macOS and Windows clients check for updates daily via Sparkle / WinSparkle. Linux and custom local builds check for new releases in **Settings → About**.

---

## Local Release Builds

```sh
flutter build macos --release     # Outputs to build/macos/Build/Products/Release/YesPlayMusic.app
flutter build windows --release   # Outputs to build/windows/x64/runner/Release/
flutter build linux --release     # Outputs to build/linux/x64/release/bundle/
```

Linux build dependencies:
`clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libmpv-dev`
