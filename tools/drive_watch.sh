#!/usr/bin/env bash
#
# drive_watch.sh -- keep the two-agent channel warm, so neither side sits waiting
# in silence on the other.
#
# WHY THIS EXISTS
#   Castor (this Mac) and Pollux (the Windows box) coordinate through ONE shared Drive
#   folder, and nothing tells either side that the other has written. That has already
#   cost real time: Pollux posted a handover, said "ready when 0.0013 lands", and the
#   Mac side only noticed the next time a human asked it to look. This watcher removes
#   that silence. It polls the shared folder, records what changed, decides whether a
#   message is waiting for a reply, and keeps a heartbeat so the other side can see
#   this machine is alive and listening.
#
# WHAT IT DOES
#   watch            poll forever (default 30 s), diffing a snapshot of every file
#   once             one poll, print what changed, exit -- for a quick look
#   digest           print everything noticed since the last `clear`
#   clear            empty the digest (after you have read it)
#   say "text"       append a message to messages/from-<agent>.md, with a timestamp
#   start|stop|status   run the poll loop in the background, or ask about it
#
# WHAT IT CANNOT DO -- AND MUST NEVER PRETEND TO
#   It cannot make an AI agent act. Nothing on this machine can wake the assistant: the
#   assistant runs only when a human talks to it. So this loop's job is to make the
#   WAITING VISIBLE -- a notification, a log line, and a digest one command away -- and
#   the human (or the next turn) does the talking. A script that faked a reply would be
#   worse than no script, because both sides would trust it.
#
# CONVENTIONS IT ENFORCES
#   * messages/from-<agent>.md is that agent's channel, keyed on the MACHINE, so both
#     sides always know where to look.
#   * HEARTBEAT-<agent>.md is written but NOT watched. It exists only so the other side
#     can see liveness; watching it would make each side's heartbeat look like news to
#     the other, and two watchers would ping-pong forever. Never put anything in it that
#     you need read.
#   * *.zip, *.tmp and dotfiles are ignored: the release zips are shared through this
#     folder too, and hashing a 44 MB zip every 30 seconds is a waste of the Drive.
#
# USAGE
#   tools/drive_watch.sh start            # background poll loop, survives this shell
#   tools/drive_watch.sh status
#   tools/drive_watch.sh digest           # what has happened since I last read it
#   tools/drive_watch.sh once             # a single look right now
#   tools/drive_watch.sh stop
#
#   COMMS_DIR=... AGENT=castor INTERVAL=30 tools/drive_watch.sh start
#
# Overridable: COMMS_DIR, AGENT, INTERVAL (seconds), HEARTBEAT_SECS (0 disables),
# NO_NOTIFY=1 to keep it silent.

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMS_DIR="${COMMS_DIR:-$HOME/Library/CloudStorage/GoogleDrive-mo.baaba@gmail.com/My Drive/agent-comms}"
AGENT="${AGENT:-castor}"
OTHER="${OTHER:-pollux}"
INTERVAL="${INTERVAL:-30}"
HEARTBEAT_SECS="${HEARTBEAT_SECS:-900}"
STATE_DIR="${STATE_DIR:-$PROJECT_DIR/dist/drive_watch}"
MAX_HASH_BYTES=4194304   # above this, size+mtime is the identity: a zip's sha is not worth a poll

LOG="$STATE_DIR/watch.log"
SNAP="$STATE_DIR/snapshot.txt"
DIGEST="$STATE_DIR/INBOX.md"
PIDFILE="$STATE_DIR/watcher.pid"
mkdir -p "$STATE_DIR" 2>/dev/null

stamp() { date "+%Y-%m-%d %H:%M:%S"; }

# ---------------------------------------------------------------------------
# One line per watched file: <relative path>|<bytes>|<mtime>|<sha256 or size tag>
# ---------------------------------------------------------------------------
snapshot() {
	local f size mtime hash rel
	find "$COMMS_DIR" -type f \
		! -name 'HEARTBEAT-*' ! -name '*.tmp' ! -name '*.zip' ! -name '.*' \
		-print 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
		size=$(stat -f %z "$f" 2>/dev/null) || continue
		mtime=$(stat -f %m "$f" 2>/dev/null)
		rel="${f#"$COMMS_DIR"/}"
		if [ "$size" -le "$MAX_HASH_BYTES" ]; then
			hash=$(shasum -a 256 "$f" 2>/dev/null | cut -d' ' -f1)
		else
			hash="big:$size:$mtime"
		fi
		printf '%s|%s|%s|%s\n' "$rel" "$size" "$mtime" "$hash"
	done
}

# Ask macOS to show a notification. Fired into the background on purpose: osascript
# can block on a permission prompt, and a watcher that stops polling because a dialog
# is waiting for a click is worse than one that says nothing.
notify() {
	local title="$1" body="$2"
	[ "${NO_NOTIFY:-0}" = "1" ] && return 0
	title="${title//\"/}"; body="${body//\"/}"; body="${body//$'\n'/ }"
	( osascript -e "display notification \"$body\" with title \"$title\" sound name \"Ping\"" >/dev/null 2>&1 & ) 2>/dev/null
	return 0
}

# The tail of a changed channel file, so the digest carries the actual words rather
# than only the fact that something moved.
tail_of() {
	local f="$1" n="${2:-14}"
	[ -f "$f" ] || return 0
	tail -n "$n" "$f" 2>/dev/null | sed 's/^/    /'
}

heartbeat() {
	local last_change="$1"
	local target="$COMMS_DIR/HEARTBEAT-$AGENT.md"
	{
		printf '# HEARTBEAT-%s.md -- watcher alive (WATCHERS IGNORE THIS FILE)\n\n' "$AGENT"
		printf 'Written by tools/drive_watch.sh on this machine. Its only purpose is so the\n'
		printf 'other side can see that this one is up and listening. Do not rely on its\n'
		printf 'contents, and do not reply to it -- watchers skip it so that two watchers\n'
		printf 'cannot ping-pong heartbeats at each other.\n\n'
		printf -- '- updated: %s\n' "$(stamp)"
		printf -- '- machine: %s\n' "$(hostname -s 2>/dev/null || echo unknown)"
		printf -- '- agent: %s\n' "$AGENT"
		printf -- '- watching: %s\n' "$COMMS_DIR"
		printf -- '- last change seen: %s\n' "$last_change"
		printf -- '- watcher pid: %s\n' "$$"
	} > "$target.tmp" 2>/dev/null && mv "$target.tmp" "$target" 2>/dev/null
	return 0
}

# ---------------------------------------------------------------------------
# One poll. Prints a human-readable list of what moved (empty when nothing did).
# ---------------------------------------------------------------------------
once() {
	if [ ! -d "$COMMS_DIR" ]; then
		echo "$(stamp) !! shared folder not reachable: $COMMS_DIR" >> "$LOG"
		return 2
	fi
	local new="$STATE_DIR/snapshot.new"
	snapshot > "$new"
	if [ ! -s "$SNAP" ]; then
		cp "$new" "$SNAP"
		echo "$(stamp) baseline: $(wc -l < "$SNAP" | tr -d ' ') files recorded" >> "$LOG"
		return 0
	fi

	# Compare path+hash only. mtime alone would report every file the Drive touches
	# (DriveFS rewrites metadata for no reason), which is noise, not news.
	awk -F'|' '{print $1" "$4}' "$SNAP" | LC_ALL=C sort > "$STATE_DIR/old.map"
	awk -F'|' '{print $1" "$4}' "$new"  | LC_ALL=C sort > "$STATE_DIR/new.map"
	local added removed edited
	added=$(comm -13 "$STATE_DIR/old.map" "$STATE_DIR/new.map" | cut -d' ' -f1)
	removed=$(comm -23 "$STATE_DIR/old.map" "$STATE_DIR/new.map" | cut -d' ' -f1)
	edited=$(join "$STATE_DIR/old.map" "$STATE_DIR/new.map" | awk '$2 != $3 {print $1}')

	if [ -z "$added$removed$edited" ]; then
		cp "$new" "$SNAP"
		return 0
	fi

	local report="" rel
	for rel in $added;   do report="$report
  NEW      $rel"; done
	for rel in $edited;  do report="$report
  CHANGED  $rel"; done
	for rel in $removed; do report="$report
  GONE     $rel"; done
	echo "$(stamp)$report" >> "$LOG"

	# Is a reply owed? That is the whole point: someone else's message moved.
	local owed=""
	case "$added $edited" in
		*"messages/from-$OTHER.md"*) owed="YES -- the other agent wrote; a reply may be owed" ;;
	esac

	{
		echo
		echo "## $(stamp)"
		echo "$report"
		[ -n "$owed" ] && echo "  >>> REPLY MAY BE OWED: $owed"
		for rel in $edited; do
			case "$rel" in
				messages/*)
					echo "  --- tail of $rel ---"
					tail_of "$COMMS_DIR/$rel" 14 ;;
			esac
		done
	} >> "$DIGEST"

	local summary
	summary=$(printf '%s' "$report" | tr '\n' ';' | cut -c1-160)
	notify "Agent channel ($AGENT)" "$summary"
	cp "$new" "$SNAP"
	return 1   # 1 = something changed, which is what `once` reports to the caller
}

watch() {
	echo "$(stamp) watching $COMMS_DIR every ${INTERVAL}s (heartbeat every ${HEARTBEAT_SECS}s)" >> "$LOG"
	local last_change="nothing yet" last_hb=0 now
	while true; do
		if once; then :; else last_change="$(stamp)"; fi
		now=$(date +%s)
		if [ "$HEARTBEAT_SECS" -gt 0 ] && [ $((now - last_hb)) -ge "$HEARTBEAT_SECS" ]; then
			last_hb=$now
			heartbeat "$last_change"
		fi
		sleep "$INTERVAL"
	done
}

# ---------------------------------------------------------------------------
case "${1:-status}" in
	once)
		once
		exit $?
		;;
	watch)
		watch
		;;
	start)
		if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
			echo "already running (pid $(cat "$PIDFILE"))"
			exit 0
		fi
		nohup "${BASH_SOURCE[0]}" watch >> "$LOG" 2>&1 &
		echo $! > "$PIDFILE"
		sleep 2
		if kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
			echo "watching $COMMS_DIR every ${INTERVAL}s (pid $(cat "$PIDFILE"))"
			echo "digest: $DIGEST    log: $LOG"
		else
			echo "!! failed to start; see $LOG" >&2
			exit 1
		fi
		;;
	stop)
		if [ -f "$PIDFILE" ]; then
			kill "$(cat "$PIDFILE")" 2>/dev/null && echo "stopped (pid $(cat "$PIDFILE"))"
			rm -f "$PIDFILE"
		else
			echo "not running"
		fi
		;;
	status)
		if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
			echo "running (pid $(cat "$PIDFILE")) -- every ${INTERVAL}s on $COMMS_DIR"
			echo "files watched: $(wc -l < "$SNAP" 2>/dev/null | tr -d ' ')"
			echo "log tail:"; tail -3 "$LOG" 2>/dev/null | sed 's/^/  /'
		else
			echo "not running"; exit 1
		fi
		;;
	digest)
		if [ -s "$DIGEST" ]; then cat "$DIGEST"; else echo "(nothing new since the last clear)"; fi
		;;
	clear)
		: > "$DIGEST"; echo "digest cleared"
		;;
	say)
		shift
		[ $# -gt 0 ] || { echo "usage: $0 say \"text\"" >&2; exit 2; }
		{
			echo
			echo "---"
			echo
			printf '### %s -- %s\n\n%s\n' "$AGENT" "$(stamp)" "$*"
		} >> "$COMMS_DIR/messages/from-$AGENT.md"
		echo "appended to messages/from-$AGENT.md"
		;;
	*)
		sed -n '2,30p' "${BASH_SOURCE[0]}"
		exit 2
		;;
esac
