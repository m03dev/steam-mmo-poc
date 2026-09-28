#!/usr/bin/env bash
#
# itch_push.sh -- put the downloadable builds on itch.io, and nothing that is broken.
#
#   tools/itch_push.sh <itch-user> <page-slug> [--dry-run] [--html5]
#
# One command, because the only things missing were always the human's: the page slug
# and `butler login`. Neither is a secret this script needs to hold -- butler reads
# ~/.config/itch/butler_creds, which Mohamed creates by running, once, himself:
#
#     ~/Applications/butler/butler login
#
# WHAT IT PUSHES, and why exactly this much:
#   windows  dist/SteamMMO_<version>.zip          (44 MB)
#   osx      dist/SteamMMO_<version>_macos.zip    (66 MB)  <- _macos, not _mac
#
# It does NOT push the html5 channel by default. That build renders its menu and is
# completely inert -- three Steam-coupled autoloads fail to PARSE in a browser, so
# every button does nothing (see ITCH.md). A broken page is worse than no page.
# `--html5` will push it, but only after tools/web_smoke.sh passes, so the flag
# cannot be used to ship the known-bad build by accident.
set -uo pipefail

BUTLER="${BUTLER:-$HOME/Applications/butler/butler}"
DRY_RUN=0
WITH_HTML5=0
ARGS=()
for a in "$@"; do
	case "$a" in
		--dry-run) DRY_RUN=1 ;;
		--html5) WITH_HTML5=1 ;;
		-h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
		-*) echo "unknown option: $a" >&2; exit 2 ;;
		*) ARGS+=("$a") ;;
	esac
done
[ "${#ARGS[@]}" -eq 2 ] || {
	echo "usage: tools/itch_push.sh <itch-user> <page-slug> [--dry-run] [--html5]" >&2
	exit 2
}
ITCH_USER="${ARGS[0]}"
SLUG="${ARGS[1]}"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
LEDGER="$PROJECT_DIR/VERSIONS.md"
VERSION="$(cat "$PROJECT_DIR/VERSION")"
CREDS="$HOME/.config/itch/butler_creds"

[ -x "$BUTLER" ] || {
	echo "!! butler not found at $BUTLER" >&2
	echo "   (it is installed there per ITCH.md; override with BUTLER=/path/to/butler)" >&2
	exit 1
}

# Refuse to push an artefact whose bytes are not the ones the ledger recorded: this is
# the difference between shipping a build and shipping a build someone edited by hand.
expect() { # file, version, label
	local file="$1" ver="$2" label="$3"
	local expected actual
	expected="$(grep -F "SteamMMO_$ver" "$LEDGER" | grep -F "($label)" \
		| grep -oE 'sha256 `[0-9a-f]{64}`' | tail -1 | tr -d '`' | awk '{print $2}')"
	[ -n "$expected" ] || {
		echo "!! no $label entry for $ver in VERSIONS.md -- cut a release first" >&2
		return 1
	}
	actual="$(shasum -a 256 "$file" | cut -d' ' -f1)"
	if [ "$expected" != "$actual" ]; then
		echo "!! $file does not match VERSIONS.md" >&2
		echo "   ledger: $expected" >&2
		echo "   disk:   $actual" >&2
		return 1
	fi
	echo "==> $label artefact verified against the ledger"
}

WIN_ZIP="$DIST_DIR/SteamMMO_$VERSION.zip"
MAC_ZIP="$DIST_DIR/SteamMMO_${VERSION}_macos.zip"
[ -f "$WIN_ZIP" ] || { echo "!! missing $WIN_ZIP" >&2; exit 1; }
[ -f "$MAC_ZIP" ] || { echo "!! missing $MAC_ZIP" >&2; exit 1; }

ok=1
expect "$WIN_ZIP" "$VERSION" "Windows" || ok=0
expect "$MAC_ZIP" "$VERSION" "macOS" || ok=0
[ "$ok" -eq 1 ] || exit 1

HTML5_DIR="$PROJECT_DIR/build/web"
if [ "$WITH_HTML5" -eq 1 ]; then
	echo "==> --html5 given: checking the browser build actually works first"
	if ! bash "$PROJECT_DIR/tools/web_smoke.sh"; then
		echo "!! web_smoke.sh says the browser build is broken -- refusing to push html5." >&2
		echo "   That is the point: the menu renders but every button is dead (see ITCH.md)." >&2
		exit 1
	fi
	[ -f "$HTML5_DIR/index.html" ] || { echo "!! no $HTML5_DIR/index.html" >&2; exit 1; }
fi

if [ "$DRY_RUN" -eq 0 ] && [ ! -f "$CREDS" ]; then
	echo "!! butler is not logged in ($CREDS is absent)." >&2
	echo "   Run this once, yourself -- it is your account, and the credential must stay yours:" >&2
	echo "       $BUTLER login" >&2
	exit 1
fi

push() { # local-path, target, what
	echo "==> butler push $3 -> $ITCH_USER/$SLUG:$2  (userversion $VERSION)"
	if [ "$DRY_RUN" -eq 1 ]; then
		echo "    (dry run: not sent)"
		return 0
	fi
	"$BUTLER" push "$1" "$ITCH_USER/$SLUG:$2" --userversion "$VERSION"
}

push "$WIN_ZIP" "windows" "the Windows zip"
push "$MAC_ZIP" "osx" "the macOS zip"
if [ "$WITH_HTML5" -eq 1 ]; then
	push "$HTML5_DIR" "html5" "the web folder"
else
	echo "==> html5 intentionally NOT pushed: that build's menu is dead in a browser"
fi

cat <<REMINDERS

==> Remember on the page itself, or the downloads get reported as broken:
    * macOS is UNSIGNED: testers will see "cannot be opened because the developer cannot
      be verified" or "it is damaged". Right-click -> Open once, or
      xattr -dr com.apple.quarantine SteamMMO.app. Say so in the page text.
    * Multiplayer: the downloads can host/join over IP (LAN works as-is; the open internet
      needs port 23460 forwarded), or over Steam. The browser build, if ever pushed, is
      single-player only -- a browser cannot open a UDP socket.
    * This same push is the update mechanism: friends get "new version available" in the
      itch app whenever a new VERSION goes up.
REMINDERS