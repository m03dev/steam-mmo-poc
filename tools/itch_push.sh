#!/usr/bin/env bash
#
# itch_push.sh -- put the downloadable builds on itch.io, and nothing that is broken.
#
#   tools/itch_push.sh [itch-user] [page-slug] [--only windows|osx] [--dry-run] [--html5]
#
# Defaults to the real page: mo3dev/testing. The only things it needs that are not
# here are the human's: the page must exist, and this machine must be authenticated
# with butler (see AUTH below).
#
# ============================================================================
# THE AUTO-UNZIP TRAP -- read this before changing anything here
# ============================================================================
# Pushing a .zip as `src` is NOT the same as pushing a directory that happens to
# contain one .zip, and the difference is invisible until someone on a Mac tries to
# open the result. Observed on butler v15.31.0:
#
#   butler push --dry-run /tmp/stage_probe mo3dev/testing:osx
#     * (/tmp/stage_probe) contains a single .zip file, treating X.zip as the container
#     drwxr-xr-x  SteamMMO.app/Contents/MacOS/           <- pushes the LOOSE TREE
#     -rwxr-xr-x  SteamMMO.app/Contents/MacOS/SteamMMO
#
#   butler push --no-auto-unzip --dry-run /tmp/stage_probe mo3dev/testing:osx
#     -rw-r--r--  63.36 MiB SteamMMO_0.0011_macos.zip     <- pushes the ZIP AS A BLOB
#     Would push 63.36 MiB (1 files, 0 dirs, 0 symlinks)
#
# Auto-unzip is the DEFAULT for a directory holding exactly one zip. This is how
# Pollux's first osx push shipped a .app that would not open on the Mac: the
# delivered bundle had lost its executable bit. It is harmless on Windows (no unix
# modes to lose) but it breaks the osx download, so this script ALWAYS pushes from a
# one-zip staging directory with --no-auto-unzip. That also makes the delivered
# artefact byte-identical to the file whose sha256 is recorded in VERSIONS.md, so the
# ledger means something end to end.
#
# Do not "simplify" this back to `butler push dist/X.zip` -- given a .zip as src,
# butler is free to unpack it too.
# ============================================================================
#
# NOT pushed: the html5 channel. That build renders its menu and every button is
# dead -- three Steam-coupled autoloads fail to PARSE in a browser, so no runtime
# guard can help (see ITCH.md). --html5 exists but runs tools/web_smoke.sh first and
# aborts while the build fails, so the flag cannot ship the known-bad build by accident.
set -uo pipefail

BUTLER="${BUTLER:-$HOME/Applications/butler/butler}"
ITCH_USER="${ITCH_USER:-mo3dev}"
SLUG="${ITCH_SLUG:-testing}"
DRY_RUN=0
WITH_HTML5=0
ONLY=""
_next_only=0
ARGS=()
for a in "$@"; do
	if [ "$_next_only" -eq 1 ]; then ONLY="$a"; _next_only=0; continue; fi
	case "$a" in
		--dry-run) DRY_RUN=1 ;;
		--html5) WITH_HTML5=1 ;;
		--only) _next_only=1 ;;
		--only=*) ONLY="${a#--only=}" ;;
		windows|osx) ARGS+=("$a") ;;
		-h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
		-*) echo "unknown option: $a" >&2; exit 2 ;;
		*) ARGS+=("$a") ;;
	esac
done
if [ "$_next_only" -eq 1 ]; then echo "--only wants windows or osx" >&2; exit 2; fi
case "$ONLY" in ""|windows|osx) ;; *) echo "--only wants windows or osx, got '$ONLY'" >&2; exit 2 ;; esac

# Positional args are optional and only there so the page can be retargeted.
if [ "${#ARGS[@]}" -ge 1 ]; then ITCH_USER="${ARGS[0]}"; fi
if [ "${#ARGS[@]}" -ge 2 ]; then SLUG="${ARGS[1]}"; fi
if [ "${#ARGS[@]}" -gt 2 ]; then
	echo "usage: tools/itch_push.sh [user] [slug] [--only windows|osx] [--dry-run] [--html5]" >&2
	exit 2
fi

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
LEDGER="$PROJECT_DIR/VERSIONS.md"
VERSION="$(cat "$PROJECT_DIR/VERSION")"

[ -x "$BUTLER" ] || {
	echo "!! butler not found at $BUTLER" >&2
	echo "   (installed there per ITCH.md; override with BUTLER=/path/to/butler)" >&2
	exit 1
}

# Refuse to push bytes that are not the ones the ledger recorded: this is the
# difference between shipping a build and shipping a build someone edited by hand.
expect() { # file, version, label
	local file="$1" ver="$2" label="$3"
	local expected actual
	expected="$(grep -F "SteamMMO_$ver" "$LEDGER" | grep -F "($label)" \
		| grep -oE 'sha256 `[0-9a-f]{64}`' | tail -1 | tr -d '`' | awk '{print $2}')"
	if [ -z "$expected" ]; then
		echo "!! no $label entry for $ver in VERSIONS.md -- cut a release first" >&2
		return 1
	fi
	actual="$(shasum -a 256 "$file" | cut -d' ' -f1)"
	if [ "$expected" != "$actual" ]; then
		echo "!! $file does not match VERSIONS.md" >&2
		echo "   ledger: $expected" >&2
		echo "   disk:   $actual" >&2
		return 1
	fi
	echo "==> $label artefact verified against the ledger (sha256 $actual)"
}

# ---------------------------------------------------------------------------
# AUTH. butler's default identity file differs per platform -- on macOS it is
# ~/Library/Application Support/itch/butler_creds, and this script used to look only
# at the Linux path, which would have refused a perfectly valid push. Look at both.
# ---------------------------------------------------------------------------
identities=(
	"$HOME/Library/Application Support/itch/butler_creds"
	"$HOME/.config/itch/butler_creds"
)
authed=0
for i in "${identities[@]}"; do if [ -f "$i" ]; then authed=1; fi; done
if [ -n "${BUTLER_API_KEY:-}" ]; then authed=1; fi

if [ "$DRY_RUN" -eq 0 ] && [ "$authed" -eq 0 ]; then
	echo "!! butler is not authenticated on this machine. Looked for:" >&2
	for i in "${identities[@]}"; do echo "     $i" >&2; done
	echo "   Run this once, yourself -- it is your account, and the credential stays yours:" >&2
	echo "       $BUTLER login" >&2
	echo "   (or set BUTLER_API_KEY from itch.io -> Settings -> API keys for one push, then revoke it)" >&2
	exit 1
fi

# ---------------------------------------------------------------------------
# Push one zip as a blob, from its own staging directory. See THE AUTO-UNZIP TRAP.
# ---------------------------------------------------------------------------
stage=""
cleanup() { if [ -n "$stage" ]; then rm -rf "$stage"; fi; }
trap cleanup EXIT
stage="$(mktemp -d "${TMPDIR:-/tmp}/itch_stage.XXXXXX")"

push_zip() { # zip-file, channel, what
	local zip="$1" channel="$2" what="$3" d
	d="$(mktemp -d "$stage/$channel.XXXX")"
	cp "$zip" "$d/"
	# One zip in the directory + --no-auto-unzip == the zip IS the artefact.
	echo "==> $what -> $ITCH_USER/$SLUG:$channel  (userversion $VERSION, zip as a blob)"
	if [ "$DRY_RUN" -eq 1 ]; then
		"$BUTLER" push --no-auto-unzip --dry-run "$d" "$ITCH_USER/$SLUG:$channel" \
			--userversion "$VERSION" 2>&1 | sed 's/^/    /'
		local rc=${PIPESTATUS[0]}
		if [ "$rc" -ne 0 ]; then echo "!! dry run for $channel failed (exit $rc)" >&2; return "$rc"; fi
	else
		"$BUTLER" push --no-auto-unzip "$d" "$ITCH_USER/$SLUG:$channel" --userversion "$VERSION"
	fi
}

ok=1
want_windows=1
want_osx=1
if [ "$ONLY" = "windows" ]; then want_osx=0; fi
if [ "$ONLY" = "osx" ]; then want_windows=0; fi

if [ "$want_windows" -eq 1 ]; then
	WIN_ZIP="$DIST_DIR/SteamMMO_$VERSION.zip"
	if [ ! -f "$WIN_ZIP" ]; then echo "!! missing $WIN_ZIP" >&2; exit 1; fi
	expect "$WIN_ZIP" "$VERSION" "Windows" || ok=0
fi
if [ "$want_osx" -eq 1 ]; then
	MAC_ZIP="$DIST_DIR/SteamMMO_${VERSION}_macos.zip"
	if [ ! -f "$MAC_ZIP" ]; then echo "!! missing $MAC_ZIP" >&2; exit 1; fi
	expect "$MAC_ZIP" "$VERSION" "macOS" || ok=0
fi
if [ "$ok" -eq 0 ]; then exit 1; fi

HTML5_DIR="$PROJECT_DIR/build/web"
if [ "$WITH_HTML5" -eq 1 ]; then
	echo "==> --html5 given: checking the browser build actually works first"
	if ! bash "$PROJECT_DIR/tools/web_smoke.sh"; then
		echo "!! web_smoke.sh says the browser build is broken -- refusing to push html5." >&2
		echo "   That is the point: the menu renders but every button is dead (see ITCH.md)." >&2
		exit 1
	fi
	if [ ! -f "$HTML5_DIR/index.html" ]; then echo "!! no $HTML5_DIR/index.html" >&2; exit 1; fi
fi

if [ "$want_windows" -eq 1 ]; then push_zip "$WIN_ZIP" "windows" "the Windows build" || ok=0; fi
if [ "$want_osx" -eq 1 ]; then push_zip "$MAC_ZIP" "osx" "the macOS build" || ok=0; fi

if [ "$WITH_HTML5" -eq 1 ]; then
	echo "==> the web folder -> $ITCH_USER/$SLUG:html5"
	if [ "$DRY_RUN" -eq 1 ]; then
		"$BUTLER" push --dry-run "$HTML5_DIR" "$ITCH_USER/$SLUG:html5" --userversion "$VERSION" 2>&1 | sed 's/^/    /'
	else
		"$BUTLER" push "$HTML5_DIR" "$ITCH_USER/$SLUG:html5" --userversion "$VERSION"
	fi
else
	echo "==> html5 intentionally NOT pushed: that build's menu is dead in a browser"
fi

if [ "$ok" -eq 0 ]; then echo "!! at least one push failed" >&2; exit 1; fi

cat <<REMINDERS

==> After a real push, confirm what the page actually SERVES (not what we sent):
	  $BUTLER fetch $ITCH_USER/$SLUG:osx --dest /tmp/itch_fetched
      shasum -a 256 /tmp/itch_fetched/*.zip     # must equal the VERSIONS.md sha
      unzip -l /tmp/itch_fetched/*.zip | head   # the .app must still be inside

==> Reminders for the page text, or the downloads get reported as broken:
    * macOS is UNSIGNED: right-click -> Open once, or
      xattr -dr com.apple.quarantine SteamMMO.app. Say so on the page.
    * Multiplayer in the downloads: Steam, or direct IP with no Steam at all
      (LAN as-is; across the internet the host forwards UDP port 23460).
      The browser build, if ever pushed, is single-player only by nature.
    * This same push is the update mechanism: the itch app offers the new version
      whenever a new VERSION goes up.
REMINDERS
