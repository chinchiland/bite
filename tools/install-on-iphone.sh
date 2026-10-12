#!/bin/bash
# Builds Bite and Bite Demo on this Mac, signed with your Apple team, and installs them on the
# iPhone plugged into it. Run it from anywhere in the repo:
#
#   tools/install-on-iphone.sh          both apps
#   tools/install-on-iphone.sh bite     only Bite, the real app
#   tools/install-on-iphone.sh demo     only Bite Demo, on two weeks of sample meals
#
# Once per Mac: Xcode 26 or later, opened once; Xcode > Settings > Accounts signed in with the
# Apple ID of team CKPJMS3P4U. Once per iPhone: plugged in, unlocked, "Trust This Computer",
# and Developer Mode on (Settings > Privacy & Security > Developer Mode).
#
# Settings you can change from the command line:
#   TEAM=XXXXXXXXXX       another Apple team (default CKPJMS3P4U)
#   BUNDLE_ID=ch.you.bite if Apple says com.dylan.bite is taken (the demo adds .demo)
#   DEVICE=<udid>         when more than one iPhone is plugged in
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM="${TEAM:-CKPJMS3P4U}"
BUNDLE_ID="${BUNDLE_ID:-com.dylan.bite}"
WHICH="${1:-both}"
case "$WHICH" in
  bite|demo|both) ;;
  *) echo "Usage: tools/install-on-iphone.sh [bite|demo|both]"; exit 1 ;;
esac
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v xcodebuild >/dev/null || { echo "Xcode is not installed, or not selected: sudo xcode-select -s /Applications/Xcode.app"; exit 1; }

# The iPhone: the one plugged in or on the same network, paired with this Mac.
if [ -z "${DEVICE:-}" ]; then
  xcrun devicectl list devices --json-output "$TMP/devices.json" >/dev/null
  DEVICE="$(python3 - "$TMP/devices.json" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1])).get("result", {}).get("devices", [])
phones = [d for d in devices
          if d.get("hardwareProperties", {}).get("platform") == "iOS"
          and d.get("connectionProperties", {}).get("pairingState") == "paired"]
# Plugged in first, then on the same network.
phones.sort(key=lambda d: {"wired": 0, "localNetwork": 1}.get(d.get("connectionProperties", {}).get("transportType"), 2))
if phones and phones[0].get("connectionProperties", {}).get("transportType"):
    print(phones[0].get("hardwareProperties", {}).get("udid", ""))
PY
)"
fi
if [ -z "$DEVICE" ]; then
  echo "No iPhone found. Plug it in, unlock it, tap Trust, turn on Developer Mode, then run this again."
  echo "Paired devices Xcode knows about:"
  xcrun devicectl list devices || true
  exit 1
fi
echo "iPhone: $DEVICE   team: $TEAM"

# One app: a Release build for this iPhone, signed automatically with the team (Xcode
# registers the device and the app id, with Apple Health, the first time), then installed.
install_app() {
  local name="$1" bundle="$2"; shift 2
  local out="build/iphone-$name"
  echo "== Building $name ($bundle)"
  xcodebuild build \
    -project Bite.xcodeproj \
    -scheme Bite \
    -configuration Release \
    -destination "platform=iOS,id=$DEVICE" \
    -derivedDataPath "$out" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_STYLE=Automatic \
    PRODUCT_BUNDLE_IDENTIFIER="$bundle" \
    "$@" \
    -quiet
  echo "== Installing $name"
  xcrun devicectl device install app --device "$DEVICE" "$out/Build/Products/Release-iphoneos/Bite.app"
  xcrun devicectl device process launch --device "$DEVICE" "$bundle" >/dev/null 2>&1 \
    || echo "   Installed. Open it on the iPhone (it launches by itself only when the phone is unlocked)."
}

case "$WHICH" in
  bite|both) install_app "Bite" "$BUNDLE_ID" ;;
esac
case "$WHICH" in
  demo|both)
    # The same app with the BITE_DEMO switch: its own name and icon, and the demo photos that
    # Release builds normally leave out.
    install_app "Bite Demo" "$BUNDLE_ID.demo" \
      INFOPLIST_KEY_CFBundleDisplayName="Bite Demo" \
      ASSETCATALOG_COMPILER_APPICON_NAME=AppIconDemo \
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) BITE_DEMO' \
      EXCLUDED_SOURCE_FILE_NAMES=
    ;;
esac
echo "Done. In Bite, tap Connect Health on Today, and paste your Claude key in Settings > Photo estimates."
