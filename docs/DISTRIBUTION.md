# Sharing and notarizing Gather

## Current shareable preview

`dist/releases/Gather-0.9.4-macOS-AppleSilicon-preview.zip` contains only Gather.app, version 0.9.4 (25). It does not include the user's screenshot library, bookmarks, preferences or signing keys. Requires Apple Silicon and macOS 14+. This is an ad-hoc-signed developer preview, not a notarized public release; Gatekeeper may block it on another Mac.

ZIP packaging uses Apple's `ditto --keepParent --sequesterRsrc`. Archive integrity and the extracted app signature are verified before delivery.

## One-time Apple setup

1. Enroll at https://developer.apple.com/programs/enroll/ and complete Apple's identity checks, agreement and membership payment yourself. Apple lists the standard fee as USD 99/year, with regional pricing where available.
2. Once membership is active, create and install a **Developer ID Application** certificate with its private key on this Mac. An Apple Development or Apple Distribution certificate is not a substitute. Use Xcode's account certificate management or the Apple Developer Certificates portal with a locally generated certificate signing request. Keep the private key on your Mac.
3. Run `security find-identity -v -p codesigning` to confirm that the certificate is a valid identity.
4. Create a notarytool Keychain profile in a local interactive terminal:

   ```sh
   xcrun notarytool store-credentials Gather-notary
   ```

   Supply your Apple account, team ID and app-specific password to the local prompts. Alternatively use Apple's supported App Store Connect API key authentication. Never commit credentials or private keys to this project.

## Release workflow

Build the current source first:

```sh
scripts/build-app.sh
scripts/notarize-app.sh --check
```

Then use the exact installed identity name:

```sh
SIGN_IDENTITY='Developer ID Application: YOUR NAME (YOUR_TEAM_ID)' \
NOTARY_PROFILE='Gather-notary' \
scripts/notarize-app.sh --submit
```

The script copies the app into its own staging directory, applies Developer ID signing with hardened runtime and a secure timestamp, verifies the signature, submits the app ZIP to Apple and waits up to ten minutes. It only creates a `-notarized.zip` release after Apple returns Accepted, the ticket is stapled and validated, and Gatekeeper assessment passes. It re-creates the final ZIP after stapling. It never changes the installed app or ad-hoc development build.

If submission times out, inspect the submission output in `.build/notarization/release.*/submission.json` and check Apple's status before submitting again; a timeout is not a rejection. No automated submission has been performed yet.

The shell syntax and missing-certificate preflight have been checked. Actual Developer ID signing, upload, stapling and Gatekeeper acceptance cannot be verified until enrollment and certificate/credential setup are complete. Before broader release, test the notarized artifact on a clean Mac, including folder access, login registration, import, search and dragging.

References: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution and https://developer.apple.com/documentation/security/customizing-the-notarization-workflow
