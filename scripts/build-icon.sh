#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source_icon="$PWD/Assets/GatherIcon.png"
output_icon="${1:-$PWD/.build/Gather.icns}"
mkdir -p "$PWD/.build" "${output_icon:h}"
staging=$(mktemp -d "$PWD/.build/gather-icon.XXXXXX")
trap 'rm -rf "$staging"' EXIT
iconset="$staging/Gather.iconset"
mkdir -p "$iconset"
# Supply each standard and Retina representation so Finder and Dock can choose
# an appropriate resolution without scaling the full-size artwork themselves.
for point_size in 16 32 128 256 512; do
    sips -z "$point_size" "$point_size" "$source_icon" --out "$iconset/icon_${point_size}x${point_size}.png" >/dev/null
    pixel_size=$((point_size * 2))
    sips -z "$pixel_size" "$pixel_size" "$source_icon" --out "$iconset/icon_${point_size}x${point_size}@2x.png" >/dev/null
done
iconutil --convert icns "$iconset" --output "$output_icon"
