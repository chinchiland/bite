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
# A build may leave out a capability your team can't sign yet; the entitlements files always
# come back as they were, even if the script stops halfway.
cp Bite.entitlements BiteWidgets.entitlements "$TMP/"
restore_entitlements() { cp "$TMP/Bite.entitlements" "$TMP/BiteWidgets.entitlements" . 2>/dev/null || true; }
trap 'restore_entitlements; rm -rf "$TMP"' EXIT

command -v xcodebuild >/dev/null || { echo "Xcode is not installed, or not selected: sudo xcode-select -s /Applications/Xcode.app"; exit 1; }

# The iPhone: the one plugged in, else one on the same network.
if [ -z "${DEVICE:-}" ]; then
  xcrun devicectl list devices --json-output "$TMP/devices.json" >/dev/null
  read -r DEVICE PAIRING <<<"$(python3 - "$TMP/devices.json" <<'PY'
import json, sys
devices = json.load(open(sys.argv[1])).get("result", {}).get("devices", [])
phones = [d for d in devices
          if d.get("hardwareProperties", {}).get("platform") == "iOS"
          and d.get("connectionProperties", {}).get("transportType")]
phones.sort(key=lambda d: {"wired": 0, "localNetwork": 1}.get(d["connectionProperties"]["transportType"], 2))
if phones:
    print(phones[0].get("hardwareProperties", {}).get("udid", ""), phones[0]["connectionProperties"].get("pairingState", ""))
PY
)" || true
  # A phone can forget this Mac, after an iOS update for one. Pairing again shows the Trust
  # prompt on it, so you don't have to unplug it and plug it back in.
  if [ -n "${DEVICE:-}" ] && [ "${PAIRING:-}" != "paired" ]; then
    echo "Unlock the iPhone, tap Trust and enter your passcode."
    xcrun devicectl manage pair --device "$DEVICE" >/dev/null
  fi
fi
if [ -z "${DEVICE:-}" ]; then
  echo "No iPhone found. Plug it in with a cable that carries data, unlock it, then run this again."
  echo "Devices Xcode knows about:"
  xcrun devicectl list devices || true
  exit 1
fi
echo "iPhone: $DEVICE   team: $TEAM"

# Xcode mounts its developer disk image on the iPhone before it builds for it, and the phone
# allows that only while it is unlocked. Without this wait the build times out after a minute
# with "The developer disk image could not be mounted".
tries=0
until ddi="$(xcrun devicectl device info ddiServices --device "$DEVICE" 2>&1)"; do
  if ! grep -qi "locked" <<<"$ddi"; then
    tail -5 <<<"$ddi"
    echo "Xcode can't set up the iPhone for development. Check that Developer Mode is on (Settings > Privacy & Security > Developer Mode), then run this again."
    exit 1
  fi
  [ "$tries" = 0 ] && echo "Unlock the iPhone and leave it on the Home Screen for a moment."
  tries=$((tries + 1))
  if [ "$tries" -gt 60 ]; then
    echo "The iPhone stayed locked. Unlock it, then run this again."
    exit 1
  fi
  sleep 5
done

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
  local dropped=""
  until build_app "$out" "$bundle" "$@"; do
    if grep -qi "No Accounts\|No Account for Team" "$TMP/build.log"; then
      # Without an Apple ID in Xcode nothing can be signed, and every capability then looks
      # refused, so say this before trying to build without any of them.
      echo "== Xcode has no Apple ID for team $TEAM. Xcode > Settings > Accounts > +, sign in, then run this again."
      exit 1
    elif [[ "$dropped" != *siwa* ]] && grep -qi "sign in with apple\|applesignin" "$TMP/build.log"; then
      # A free Apple team can't sign Sign in with Apple. Everything else works without it (only
      # sharing a count to the community needs it), so build once more without that capability.
      echo "== Your team can't sign Sign in with Apple: building without it (only community sharing needs it)"
      /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.applesignin" Bite.entitlements
      dropped+=" siwa"
    elif [[ "$dropped" != *group* ]] && grep -qi "application-groups" "$TMP/build.log"; then
      # Xcode registers an App Group only from its Signing & Capabilities pane, never from the
      # command line. Until group.$bundle exists, the app keeps the log in its own folder and
      # moves it into the group the first time a build has it, so nothing is lost.
      echo "== group.$bundle isn't registered with Apple yet: building without it (the widgets say Open Bite once)"
      /usr/libexec/PlistBuddy -c "Delete :com.apple.security.application-groups" Bite.entitlements
      /usr/libexec/PlistBuddy -c "Delete :com.apple.security.application-groups" BiteWidgets.entitlements
      dropped+=" group"
    else
      exit 1
    fi
  done
  restore_entitlements
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
