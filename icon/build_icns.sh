#!/bin/bash
# Regenerate AppIcon.icns from a 1024+ square source PNG (default: the Higgsfield render).
# Requires: python3 + Pillow, sips, iconutil (all on macOS with Command Line Tools + pip Pillow).
set -euo pipefail
cd "$(dirname "$0")"

SRC="${1:-higgsfield_icon.png}"
echo "==> Masking $SRC into a native icon master"
python3 make_icns.py "$SRC" icon_master_1024.png

echo "==> Generating iconset"
rm -rf AppIcon.iconset && mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
    sips -z $s $s icon_master_1024.png --out "AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d icon_master_1024.png --out "AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done

echo "==> Building AppIcon.icns"
iconutil -c icns AppIcon.iconset -o AppIcon.icns
echo "==> Done: $(pwd)/AppIcon.icns"
