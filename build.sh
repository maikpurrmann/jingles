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
mkdir -p "$app/Contents/MacOS"
cp Info.plist "$app/Contents/Info.plist"
/usr/bin/swiftc -O -swift-version 5 -parse-as-library \
    -target "$(uname -m)-apple-macosx13.0" \
    Sources/JinglesApp.swift Sources/StreamDeckControl.swift -o "$app/Contents/MacOS/Jingles"
/usr/bin/codesign --force --sign - "$app"
/usr/bin/codesign --verify --strict "$app"
rm -rf -- build/Jingles.app
mv "$app" build/Jingles.app
if (( $# )); then
    mkdir -p "$HOME/Applications"
    /usr/bin/ditto build/Jingles.app "$HOME/Applications/Jingles.app"
    /usr/bin/codesign --verify --strict "$HOME/Applications/Jingles.app"
    print -r -- "$HOME/Applications/Jingles.app"
else
    print -r -- "$PWD/build/Jingles.app"
fi
