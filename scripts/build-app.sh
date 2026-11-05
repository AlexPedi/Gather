#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache"
configuration="${CONFIGURATION:-release}"
build_args=(--disable-sandbox --cache-path .build/cache -c "$configuration" --product Gather)
# Omit debug symbols for the local optimized bundle; avoids dsymutil requiring
# access outside the workspace in restricted Command Line Tools environments.
if [[ "$configuration" == "release" ]]; then
    build_args+=(-debug-info-format none)
fi
swift build "${build_args[@]}"
bin_dir=$(swift build "${build_args[@]}" --show-bin-path)
mkdir -p "$PWD/dist"
staging=$(mktemp -d "$PWD/dist/.gather-build.XXXXXX")
trap 'rm -rf "$staging"' EXIT
app="$staging/Gather.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Gather" "$app/Contents/MacOS/Gather"
cp scripts/Info.plist "$app/Contents/Info.plist"
"$PWD/scripts/build-icon.sh" "$app/Contents/Resources/Gather.icns"
# Local ad-hoc signature. Supply SIGN_IDENTITY for a configured Developer ID identity.
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$app"
else
    codesign --force --sign - "$app"
fi
# Replace the bundle without overwriting an executable that may currently be running.
if [[ -d "$PWD/dist/Gather.app" ]]; then
    mv "$PWD/dist/Gather.app" "$staging/Previous.app"
fi
mv "$app" "$PWD/dist/Gather.app"
print "Built $PWD/dist/Gather.app"
