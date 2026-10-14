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
build_app() {
  local out="$1" bundle="$2"; shift 2
  xcodebuild build \
    -project Bite.xcodeproj \
    -scheme Bite \
    -configuration Release \
    -destination "platform=iOS,id=$DEVICE" \
    -derivedDataPath "$out" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_STYLE=Automatic \
    BITE_BUNDLE_ID="$bundle" \
    "$@" \
    -quiet 2>&1 | tee "$TMP/build.log"
  return "${PIPESTATUS[0]}"
}

install_app() {
  local name="$1" bundle="$2"; shift 2
  local out="build/iphone-$name"
  echo "== Building $name ($bundle)"
  if ! build_app "$out" "$bundle" "$@"; then
    # A free Apple team can't sign Sign in with Apple. Everything else works without it (only
    # sharing a count to the community needs it), so build once more without that capability.
    if grep -qi "sign in with apple\|applesignin" "$TMP/build.log"; then
      echo "== Your team can't sign Sign in with Apple: building without it (only community sharing needs it)"
      cp Bite.entitlements "$TMP/Bite.entitlements.saved"
      trap 'cp "$TMP/Bite.entitlements.saved" Bite.entitlements 2>/dev/null; rm -rf "$TMP"' EXIT
      /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.applesignin" Bite.entitlements
      local status=0
      build_app "$out" "$bundle" "$@" || status=$?
      cp "$TMP/Bite.entitlements.saved" Bite.entitlements
      [ "$status" -eq 0 ] || exit "$status"
    else
      exit 1
    fi
  fi
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
      BITE_APP_ICON=AppIconDemo \
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) BITE_DEMO' \
      EXCLUDED_SOURCE_FILE_NAMES=
    ;;
esac
echo "Done. In Bite, tap Connect Health on Today. Your mirror is in Settings > Your mirror."
