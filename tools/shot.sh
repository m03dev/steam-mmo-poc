#!/usr/bin/env bash
#
# shot.sh -- one screenshot of the running game, for the store page or a bug report.
#
#   tools/shot.sh --out dist/screenshots/x.png [--wait 8] [--size 1280x720]
#                 [--pos 0,0] [--keep] [--kill-all] [-- <game launch args>]
#
# The game is launched windowed and always-on-top (so a stray editor window cannot
# cover it), captured, then closed.
#
# WHY THE +60: Godot has no --borderless, so the capture rect has to be the window's
# CLIENT area rather than the window frame. Measured on this machine: macOS places a
# window requested at y=0 just below the ~28px menu bar and the ~30px title bar sits
# inside that, so the content of a window asked for at 0,0 starts at y=60. Measured,
# not guessed: capture 0,0,1280,780 once and look at where the black area begins.
#
# PROCESS HANDLING, and why there is no `pkill` here: an earlier version ended with
#   pkill -f "Godot_mono.app/Contents/MacOS/Godot --path ."
# `pkill -f` treats that as a REGEX, and `.` matches any character -- so it also
# matches the editor's own `--path /Users/...` command line. It survived that time,
# but a screenshot tool must never be one regex away from killing the editor. This
# version records the exact PID it launched and kills only that.
#
# --keep launches without capturing or killing, and appends the pid to $PID_FILE, so
# two peers can be captured in one image:
#   tools/shot.sh --keep --pos 0,0   --size 900x506 --wait 10 -- --host-direct
#   tools/shot.sh --keep --pos 920,0 --size 900x506 --wait 14 -- --join-direct=127.0.0.1
#   screencapture -x -R 0,60,1820,506 out.png
#   tools/shot.sh --kill-all
set -o pipefail

GODOT="${GODOT:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="/tmp/shot_pids"
LOG_FILE="/tmp/shot_last_log.txt"
OUT=""
WAIT=8
SIZE="1280x720"
POS="0,0"
KEEP=0
KILL_ALL=0
GAME_ARGS=()

while [ $# -gt 0 ]; do
	case "$1" in
		--out) OUT="$2"; shift 2 ;;
		--wait) WAIT="$2"; shift 2 ;;
		--size) SIZE="$2"; shift 2 ;;
		--pos) POS="$2"; shift 2 ;;
		--keep) KEEP=1; shift ;;
		--kill-all) KILL_ALL=1; shift ;;
		--) shift; GAME_ARGS=("$@"); break ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
done

kill_pids() {
	local pid
	[ -f "$PID_FILE" ] || return 0
	while read -r pid; do
		[ -n "$pid" ] || continue
		kill "$pid" 2>/dev/null && echo "==> stopped pid $pid"
	done < "$PID_FILE"
	: > "$PID_FILE"
}

if [ "$KILL_ALL" -eq 1 ]; then
	kill_pids
	exit 0
fi

W="${SIZE%x*}"
H="${SIZE#*x}"
PX="${POS%,*}"
PY="${POS#*,}"
RECT="$PX,$((PY + 60)),$W,$H"

echo "==> launching (${GAME_ARGS[*]:-no game args}) as window ${SIZE} at ${POS}"
if [ "${#GAME_ARGS[@]}" -gt 0 ]; then
	( cd "$PROJECT_DIR" && exec "$GODOT" --path . --windowed --resolution "$SIZE" \
		--position "$POS" --always-on-top -- "${GAME_ARGS[@]}" ) > "$LOG_FILE" 2>&1 &
else
	( cd "$PROJECT_DIR" && exec "$GODOT" --path . --windowed --resolution "$SIZE" \
		--position "$POS" --always-on-top ) > "$LOG_FILE" 2>&1 &
fi
GAME_PID=$!
disown "$GAME_PID" 2>/dev/null || true
echo "==> pid $GAME_PID  (log: $LOG_FILE)"

sleep "$WAIT"

if [ "$KEEP" -eq 1 ]; then
	echo "$GAME_PID" >> "$PID_FILE"
	echo "==> left running; client area is the rect $RECT"
	exit 0
fi

if [ -z "$OUT" ]; then
	echo "!! --out is required unless --keep/--kill-all is given" >&2
	kill "$GAME_PID" 2>/dev/null
	exit 2
fi

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
screencapture -x -R "$RECT" "$OUT"
if [ -f "$OUT" ]; then
	echo "==> wrote $OUT ($(stat -f%z "$OUT") bytes)"
else
	echo "!! capture failed -- is Screen Recording permission granted?" >&2
	kill "$GAME_PID" 2>/dev/null
	exit 1
fi

kill "$GAME_PID" 2>/dev/null
sleep 1
echo "==> game closed"
