#!/bin/zsh
set -euo pipefail

cd -- "${0:A:h}"
if (( $# )) && [[ $1 != --install || $# != 1 ]]; then
    print -u2 'Aufruf: ./build.sh [--install]'
    exit 2
fi

mkdir -p build
staging=$(mktemp -d "${PWD}/build/staging.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT
app="$staging/Jingles.app"
iconset="$staging/AppIcon.iconset"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$iconset"
cp Info.plist "$app/Contents/Info.plist"
for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" Resources/AppIcon.png \
        --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    /usr/bin/sips -z "$double" "$double" Resources/AppIcon.png \
        --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
/usr/bin/swiftc -O -swift-version 5 -parse-as-library \
    -target "$(uname -m)-apple-macosx13.0" \
    Sources/*.swift -o "$app/Contents/MacOS/Jingles"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --strict "$app"
if (( $# )); then
    mkdir -p "$HOME/Applications"
    /usr/bin/ditto "$app" "$HOME/Applications/Jingles.app"
    /usr/bin/codesign --verify --strict "$HOME/Applications/Jingles.app"
    if [[ -d build/Jingles.app ]]; then
        mv build/Jingles.app "$staging/previous-build"
    fi
    print -r -- "$HOME/Applications/Jingles.app"
else
    if [[ -d build/Jingles.app ]]; then
        mv build/Jingles.app "$staging/previous-build"
    fi
    mv "$app" build/Jingles.app
    print -r -- "$PWD/build/Jingles.app"
fi
