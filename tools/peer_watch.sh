#!/usr/bin/env bash
#
# peer_watch.sh - watch a RUNNING HOST's log for the moment another machine attaches to it, and
# put that evidence in the channel.
#
# Why this exists: the two-machine check cannot be completed by either agent alone. Neither can
# drive the other's PC, and neither is awake when the other acts - the last attempt ran a joiner
# window that expired while nobody was there to hear it. So the check reports itself instead of
# waiting for a rendezvous.
#
# Run it on the HOST side before telling the peer to join. When they do, the host's OWN console
# line lands in the channel without anyone being awake to copy it across.
#
#   tools/peer_watch.sh start [logfile]   start watching (default /tmp/host18.log)
#   tools/peer_watch.sh status            running? what has it seen?
#   tools/peer_watch.sh stop              stop watching
#   tools/peer_watch.sh --selftest        prove the detector fires on a real-format line
#
# It reports EVIDENCE, never a verdict. It copies the host's console verbatim and says nothing about
# whether the join was good, because a watcher that judges is a watcher that lies.
set -u

MODE="${1:-}"
LOG="${2:-/tmp/host18.log}"
STATE_DIR="${PEER_WATCH_DIR:-/tmp/peer_watch}"
PIDFILE="$STATE_DIR/pid"
WATERMARK="$STATE_DIR/watermark"
CHANNEL="${PEER_WATCH_CHANNEL:-$HOME/Library/CloudStorage/GoogleDrive-mo.baaba@gmail.com/My Drive/agent-comms/messages/from-castor.md}"
NEEDLE="attached (peer"

# The exact line the host prints when a peer connects, straight from NetworkManager:
#   [NetworkManager] <persona> attached (peer <id>, steamid <id>) - its build: game X protocol Y
new_lines() {
	local log="$1" from=0 total
	# The state dir has to exist before the watermark can be written: --scan is called directly by
	# the selftest, without going through start, and a watermark that cannot be written makes every
	# scan see the whole log again - the same join reported forever. Caught by --selftest.
	mkdir -p "$(dirname "$WATERMARK")"
	[ -f "$WATERMARK" ] && from="$(cat "$WATERMARK")"
	[ -f "$log" ] || return 0
	total="$(wc -l < "$log" | tr -d ' ')"
	if [ "$total" -gt "$from" ]; then
		tail -n "+$((from + 1))" "$log" | grep -aF "$NEEDLE" || true
	fi
	printf '%s' "$total" > "$WATERMARK"
}

watch() {
	mkdir -p "$STATE_DIR"
	while true; do
		sleep 10
		hit="$(new_lines "$LOG")"
		if [ -n "$hit" ]; then
			{
				printf '\n\n---\n\n### Castor (Mac) | %s UTC\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
				printf '## ANOTHER MACHINE ATTACHED to the world Castor is hosting\n\n'
				printf 'Verbatim from the host console, unedited:\n\n'
				printf '%s\n' "$hit" | sed 's/^/    /'
				printf '\nCastor did not witness this and claims nothing beyond the lines above.\n'
			} >> "$CHANNEL"
		fi
	done
}

start() {
	mkdir -p "$STATE_DIR"
	if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
		echo "already watching (pid $(cat "$PIDFILE"))"
		return 0
	fi
	# Start from the LIVE end of the log: yesterday's joins are not evidence about today.
	[ -f "$LOG" ] && wc -l < "$LOG" | tr -d ' ' > "$WATERMARK"
	nohup bash "$0" --watch "$LOG" > "$STATE_DIR/watch.log" 2>&1 &
	echo $! > "$PIDFILE"
	echo "watching $LOG for a peer attaching; evidence goes to $CHANNEL"
}

status() {
	if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
		echo "RUNNING pid $(cat "$PIDFILE") watching $LOG"
	else
		echo "NOT RUNNING"
	fi
	echo "watermark $(cat "$WATERMARK" 2>/dev/null || echo 0) of $(wc -l < "$LOG" 2>/dev/null | tr -d ' ' || echo 0) lines of $LOG"
	echo "evidence so far:"
	if grep -aF "$NEEDLE" "$LOG" 2>/dev/null | sed 's/^/  /' | grep .; then :; else echo "  none"; fi
}

stop() {
	if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
		kill "$(cat "$PIDFILE")" 2>/dev/null
		rm -f "$PIDFILE"
		echo "stopped"
	else
		rm -f "$PIDFILE"
		echo "was not running"
	fi
}

selftest() {
	local dir pass=0
	dir="$(mktemp -d)"
	cat > "$dir/log" <<'LOG'
[NetworkManager] SteamMMO v0.0018 | netcode protocol 3
[NetworkManager] Hosting 'world' lobby 109775243299034475. My peer id: 1.
[NetworkManager] ma.culo attached (peer 67402197, steamid 76561198632049032) - its build: game 0.0018 protocol 3
[Level/world] spawning player_67402197
LOG
	# The state paths were computed at the top of the script, so exporting PEER_WATCH_DIR here would
	# be too late to matter - the test would scan with the LIVE watermark and report a false "not
	# detected". Point the paths themselves at the scratch dir, which is what the test means.
	STATE_DIR="$dir"
	WATERMARK="$dir/watermark"
	PIDFILE="$dir/pid"
	local first second
	first="$(new_lines "$dir/log")"
	second="$(new_lines "$dir/log")"
	if ! printf '%s' "$first" | grep -qF "ma.culo attached (peer 67402197"; then
		echo "VERDICT: FAIL - the attach line was not detected at all."
	elif [ "$(printf '%s\n' "$first" | wc -l | tr -d ' ')" != "1" ]; then
		echo "VERDICT: FAIL - detected, but not exactly one line:"
		printf '%s\n' "$first"
	elif [ -n "$second" ]; then
		echo "VERDICT: FAIL - the same line was reported twice:"
		printf '%s\n' "$second"
	elif grep -aF "$NEEDLE" "$dir/log" | grep -q "Hosting"; then
		echo "VERDICT: FAIL - caught a non-join line."
	else
		echo "VERDICT: PASS - caught the attach line once, skipped the console noise, and did not"
		echo "repeat it - so a peer joining after the watcher started is reported exactly once."
		pass=1
	fi
	rm -rf "$dir"
	[ "$pass" = "1" ]
}

case "$MODE" in
	start) start ;;
	stop) stop ;;
	status) status ;;
	--watch) watch ;;
	--scan) new_lines "$LOG" ;;
	--selftest) selftest ;;
	*) echo "usage: tools/peer_watch.sh start|status|stop|--selftest   (or --watch/--scan for internal use)"; exit 2 ;;
esac
