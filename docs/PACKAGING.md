# Build and package a macOS app

## Local development bundle

```sh
./scripts/build.sh
codesign --verify --deep --strict dist/PyLabNative.app
open dist/PyLabNative.app
```

The script builds an arm64 executable targeting macOS 26, copies `Info.plist` and the two Python resources, then signs with a local ad-hoc signature. The app requires an external compatible Python installation. It is not a universal Intel/Apple Silicon binary and does not bundle or relocate Conda.

## Development ZIP

```sh
mkdir -p package/PyLab-0.7.3
ditto dist/PyLabNative.app package/PyLab-0.7.3/PyLabNative.app
cp README.md VALIDATION.md package/PyLab-0.7.3/
cp -R docs Examples package/PyLab-0.7.3/
ditto -c -k --sequesterRsrc --keepParent package/PyLab-0.7.3 PyLab-0.7.3-macos-arm64.zip
shasum -a 256 PyLab-0.7.3-macos-arm64.zip
```

App binaries belong in GitHub release assets; `dist`, generated packages and local environments are excluded from source history. Release notes should name macOS/architecture, version/build, Python dependencies, signature/notarization state, checksum, and tested limitations.

## Developer ID distribution

For a broadly distributed app, use an Apple Developer account and a Developer ID Application certificate, sign all embedded code inside-out, enable the hardened runtime, and notarize a release archive. This project embeds only its executable and Python text resources; review any future embedded runtime/framework separately.

A release-maintainer outline, with your actual signing identity and a Keychain-stored notarization profile:

```sh
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: YOUR LEGAL NAME (TEAMID)" dist/PyLabNative.app
codesign --verify --deep --strict --verbose=2 dist/PyLabNative.app
ditto -c -k --sequesterRsrc --keepParent dist/PyLabNative.app PyLab-notarization.zip
xcrun notarytool submit PyLab-notarization.zip --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple dist/PyLabNative.app
xcrun stapler validate dist/PyLabNative.app
spctl --assess --type execute --verbose=2 dist/PyLabNative.app
```

Those steps require real account/certificate configuration; no credentials are stored in this repository. Test Python launch and kernel lifecycle on a clean Mac after signing. Signing/notarization does not install scientific Python or provide process isolation. See Apple's [distribution preparation guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) for current requirements.

## Swift package and resources

The Swift package supports editing/building in Xcode. The bundle script is the release path because it provides the app's `Info.plist` and predictable resource locations. The controller first looks for bridge resources in the app bundle and has a source-checkout fallback for standalone development tests. Do not distribute a raw Swift executable assuming that source fallback will exist on another computer.
