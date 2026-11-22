#!/bin/zsh
set -euo pipefail

cd -- "${0:A:h}"
mode=${1:-}
if (( $# > 1 )) || [[ -n $mode && $mode != --install && $mode != --preview ]]; then
    print -u2 'Aufruf: ./build.sh [--install | --preview]'
    exit 2
fi

app_name=Jingles
if [[ $mode == --preview ]]; then
    app_name='Jingles Vorschau'
fi

mkdir -p build
staging=$(mktemp -d "${PWD}/build/staging.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT
app="$staging/$app_name.app"
iconset="$staging/AppIcon.iconset"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$iconset"
cp Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :JinglesBuildDate string $(TZ=Europe/Berlin /bin/date +%d.%m.%Y)" \
    "$app/Contents/Info.plist"
if [[ $mode == --preview ]]; then
    /usr/libexec/PlistBuddy \
        -c "Set :CFBundleDisplayName $app_name" \
        -c "Set :CFBundleName $app_name" \
        -c 'Set :CFBundleIdentifier de.maikpurrmann.jingles.preview' \
        -c 'Add :JinglesStreamDeckPort integer 17640' \
        "$app/Contents/Info.plist"
fi
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
if [[ $mode == --install ]]; then
    mkdir -p "$HOME/Applications"
    /usr/bin/ditto "$app" "$HOME/Applications/Jingles.app"
    /usr/bin/codesign --verify --strict "$HOME/Applications/Jingles.app"
    if [[ -d build/Jingles.app ]]; then
        mv build/Jingles.app "$staging/previous-build"
    fi
    print -r -- "$HOME/Applications/Jingles.app"
else
    destination="build/$app_name.app"
    if [[ -d $destination ]]; then
        mv "$destination" "$staging/previous-build"
    fi
    mv "$app" "$destination"
    print -r -- "$PWD/$destination"
fi
