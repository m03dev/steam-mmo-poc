#!/usr/bin/env bash
#
# web_smoke.sh -- does the WEB build actually work, or does it only look like it?
#
#   tools/web_smoke.sh [--port N] [--wait S] [--keep-open]
#
# WHY THIS EXISTS. A web export can boot, draw its menu and still be completely
# inert, because the game's own console output goes to the browser's console and
# nothing on the developer's machine sees it. That is exactly what happened here:
# SteamMMO's web build renders a perfect start screen whose buttons do nothing,
# because three Steam-coupled autoloads fail to PARSE in a browser (there is no
# `Steam` global and no `SteamMultiplayerPeer` type in wasm). Headless Chrome
# never showed it either -- it stops at the loading splash and reports nothing.
#
# So this runs a REAL browser in its own profile, captures the game's console
# output, and greps for the fatal lines. It does not judge gameplay; it judges
# "did the engine refuse to load something", which is the failure that looks
# like success.
#
# It captures ONLY the browser window's rectangle, never the whole screen: a
# full-screen grab on a working machine catches whatever else is open on it.
# `screencapture` needs Screen Recording permission for the invoking terminal;
# without it the picture comes out blank or desktop-only, which is a permission
# problem, not a verdict on the build.
set -uo pipefail

PORT=8124
WAIT=35
KEEP_OPEN=0
while [ $# -gt 0 ]; do
	case "$1" in
		--port) PORT="$2"; shift 2 ;;
		--wait) WAIT="$2"; shift 2 ;;
		--keep-open) KEEP_OPEN=1; shift ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_DIR="$PROJECT_DIR/build/web"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
LOGDIR="${TMPDIR:-/tmp}/steammmo_web_smoke"
CONSOLE_LOG="$LOGDIR/console.log"
SHOT="$LOGDIR/screen.png"
mkdir -p "$LOGDIR"

[ -f "$WEB_DIR/index.html" ] || {
	echo "!! no web build at $WEB_DIR -- run: tools/release.sh \"note\"  (or export the Web preset)" >&2
	exit 1
}
[ -x "$CHROME" ] || {
	echo "!! Chrome not found at $CHROME -- this check needs a real browser" >&2
	exit 1
}

echo "==> serving $WEB_DIR on http://localhost:$PORT/"
( cd "$WEB_DIR" && exec python3 -m http.server "$PORT" >"$LOGDIR/http.log" 2>&1 ) &
SERVER_PID=$!
CHROME_PID=""
cleanup() {
	[ -n "$CHROME_PID" ] && kill "$CHROME_PID" 2>/dev/null
	kill "$SERVER_PID" 2>/dev/null
}
trap cleanup EXIT

# Wait for the server to answer rather than sleeping a guessed amount.
for _ in $(seq 1 40); do
	curl -sf -o /dev/null "http://localhost:$PORT/" && break
	sleep 0.25
done
curl -sf -o /dev/null "http://localhost:$PORT/" || {
	echo "!! the server on port $PORT never answered" >&2
	exit 1
}

echo "==> launching a real Chrome (own profile, so your own windows are untouched)"
# A separate --user-data-dir is what makes this a separate instance: `open -a` on
# an already-running Chrome just focuses it and IGNORES these flags (which is how
# an earlier attempt captured the wrong window entirely).
rm -rf "$LOGDIR/chrome-profile"
"$CHROME" \
	--user-data-dir="$LOGDIR/chrome-profile" \
	--no-first-run --no-default-browser-check \
	--window-position=0,0 --window-size=1280,800 \
	--new-window --enable-logging=stderr --v=1 \
	"http://localhost:$PORT/" >"$CONSOLE_LOG" 2>&1 &
CHROME_PID=$!

echo "==> letting it load for ${WAIT}s"
sleep "$WAIT"

screencapture -x -R 0,0,1280,800 "$SHOT" 2>/dev/null || true
[ -s "$SHOT" ] && echo "==> picture: $SHOT ($(stat -f '%z' "$SHOT") bytes)"

# The game's console output arrives as CONSOLE lines in Chrome's stderr log; the
# message can contain quotes, so cut the line rather than matching a quoted group.
echo
echo "===== the game's own output ====="
grep -aE "CONSOLE" "$CONSOLE_LOG" \
	| sed -E 's/^.*CONSOLE:[0-9]+\] //; s/", source: .*$//' \
	| grep -avE "^(Godot Engine|OpenGL API|Build configuration)" \
	| sed -E 's/^/  /' | head -60

echo
echo "===== verdict ====="
FATAL=0
if grep -aqE "Failed to instantiate an autoload" "$CONSOLE_LOG"; then
	echo "  FAIL: an autoload did not instantiate -- the game is missing a core singleton"
	grep -aoE "Failed to instantiate an autoload[^\"]*" "$CONSOLE_LOG" | sort -u | sed -E 's/^/    /'
	FATAL=1
fi
if grep -aqE "SCRIPT ERROR: Parse Error" "$CONSOLE_LOG"; then
	echo '  FAIL: a script failed to PARSE. On web this usually means the script names'
	echo '        something that only exists on desktop (the `Steam` global, or a'
	echo '        GodotSteam type like SteamMultiplayerPeer). A runtime guard cannot'
	echo '        catch this: the whole script is rejected before it can run.'
	grep -aoE "GDScript::reload \(res://[a-zA-Z0-9_/]+\.gd" "$CONSOLE_LOG" | sort -u | sed -E 's/^/    /'
	FATAL=1
fi
if [ "$FATAL" -eq 0 ]; then
	echo "  no fatal load errors seen. That is NOT the same as 'the game works': this"
	echo "  check cannot press a button. Open the picture and drive it by hand."
fi
if [ "$KEEP_OPEN" -eq 1 ]; then
	echo "  (--keep-open: leaving the browser up on http://localhost:$PORT/)"
	trap - EXIT
	wait "$CHROME_PID"
else
	echo
	echo "==> done. Browser and server will be closed."
fi
exit "$FATAL"