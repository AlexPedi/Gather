#!/bin/zsh
# Developer ID release workflow. Never changes the installed or local development app.
set -euo pipefail
cd "${0:A:h:h}"
mode="${1:---check}"
if [[ "$mode" != "--check" && "$mode" != "--submit" ]]; then
    print -u2 'Usage: scripts/notarize-app.sh [--check|--submit]'; exit 2
fi
xcrun --find notarytool >/dev/null
xcrun --find stapler >/dev/null
identities=$(security find-identity -v -p codesigning)
if [[ "$mode" == "--check" ]]; then
    print -r -- "$identities"
    if [[ "$identities" != *'Developer ID Application:'* ]]; then
        print -u2 'Next: enroll in the Apple Developer Program and install a Developer ID Application certificate with its private key.'
        exit 1
    fi
    print 'Developer ID identity available. Configure SIGN_IDENTITY and a notarytool keychain profile before --submit.'
    exit 0
fi
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your exact Developer ID Application certificate name.}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool keychain profile name.}"
if [[ "$SIGN_IDENTITY" != 'Developer ID Application:'* ]] || [[ "$identities" != *"\"$SIGN_IDENTITY\""* ]]; then
    print -u2 'SIGN_IDENTITY must match a valid Developer ID Application identity in your keychain.'; exit 1
fi
app_source="$PWD/dist/Gather.app"
[[ -d "$app_source" ]] || { print -u2 'Build dist/Gather.app first with scripts/build-app.sh.'; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_source/Contents/Info.plist")
[[ "$version" == [0-9]* && "$version" != *[^0-9.]* ]] || { print -u2 'Invalid app version'; exit 1; }
mkdir -p "$PWD/.build/notarization" "$PWD/dist/releases"
release_work=$(mktemp -d "$PWD/.build/notarization/release.XXXXXX")
release_app="$release_work/Gather.app"
ditto "$app_source" "$release_app"
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$release_app"
codesign --verify --deep --strict --verbose=2 "$release_app"
# ZIP is the upload container; the app inside it is stapled after acceptance.
submission_zip="$release_work/submission.zip"
ditto -c -k --sequesterRsrc --keepParent "$release_app" "$submission_zip"
print 'Uploading the signed Gather app to Apple for notarization…'
xcrun notarytool submit "$submission_zip" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 10m --output-format json > "$release_work/submission.json"
result=$(/usr/bin/plutil -extract status raw -o - "$release_work/submission.json")
if [[ "$result" != Accepted ]]; then
    print -u2 "Notarization status: $result. Inspect $release_work/submission.json; no release ZIP was created."
    exit 1
fi
xcrun stapler staple "$release_app"
xcrun stapler validate "$release_app"
codesign --verify --deep --strict --verbose=2 "$release_app"
spctl --assess --type execute --verbose=2 "$release_app"
release_zip="$PWD/dist/releases/Gather-$version-macOS-AppleSilicon-notarized.zip"
[[ ! -e "$release_zip" ]] || { print -u2 "Refusing to overwrite $release_zip"; exit 1; }
ditto -c -k --sequesterRsrc --keepParent "$release_app" "$release_zip"
unzip -tq "$release_zip"
shasum -a 256 "$release_zip" > "$release_zip.sha256"
print "Verified notarized release: $release_zip"
