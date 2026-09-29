#!/usr/bin/env bash
# auto_join.sh -- join the Windows peer's lobby the moment he says he is hosting.
#
# Why this exists: the last two-machine run failed for a reason that had nothing to do with the
# code. He hosted, asked for a second player, and nobody arrived, because an agent only runs when
# a human speaks and his window was four minutes long. A rendezvous that depends on me being
# awake at the right minute is a rendezvous that fails. This watches his message file and joins
# on its own, so the half that cannot be awake is not the half that is needed.
#
# It is deliberately narrow: it only fires on NEWLY appended text from Pollux that looks like a
# hosting announcement, it fires ONCE, and it stops itself after the run. It never writes code,
# never cuts a version, and never signs in anywhere.
#
#   tools/auto_join.sh once     # poll for TIMEOUT seconds, join once, report, exit
#   tools/auto_join.sh status   # is it running, and what has it seen
#   tools/auto_join.sh stop
set -u
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMMS_DIR="${COMMS_DIR:-$HOME/Library/CloudStorage/GoogleDrive-mo.baaba@gmail.com/My Drive/agent-comms}"
MSG="$COMMS_DIR/messages/from-pollux.md"
APP="${APP:-$PROJECT_DIR/build/served_0015/SteamMMO.app/Contents/MacOS/SteamMMO}"
OUT="${OUT:-$PROJECT_DIR/dist/castre_test}"
TOTAL_WAIT="${TOTAL_WAIT:-1500}"   # how long to wait for a hosting announcement
RUN_WINDOW="${RUN_WINDOW:-330}"    # how long to stay in the session once joined
PIDFILE="$OUT/auto_join.pid"
LOG="$OUT/auto_join.log"
GAMELOG="$OUT/joiner.log"
RESULT="$OUT/RESULT.md"

mkdir -p "$OUT"
say() { printf '%s  %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >> "$LOG"; }
count() { grep -ac -- "$1" "$GAMELOG" 2>/dev/null | head -1 || echo 0; }

case "${1:-once}" in
  stop)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      kill "$(cat "$PIDFILE")" 2>/dev/null; rm -f "$PIDFILE"; echo "stopped"
    else echo "not running"; fi
    exit 0;;
  status)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then echo "running (pid $(cat "$PIDFILE"))"; else echo "not running"; fi
    tail -5 "$LOG" 2>/dev/null; [ -f "$RESULT" ] && { echo "--- last result:"; cat "$RESULT"; }
    exit 0;;
esac

[ -x "$APP" ] || { echo "no served app at $APP" >&2; exit 1; }
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT
OFFSET=$(wc -c < "$MSG" 2>/dev/null || echo 0)
say "armed: waiting up to ${TOTAL_WAIT}s for NEW text in from-pollux.md; app=$(basename "$(dirname "$(dirname "$APP")")")"
deadline=$(( $(date +%s) + TOTAL_WAIT ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  sleep 15
  now=$(wc -c < "$MSG" 2>/dev/null || echo 0)
  [ "$now" -le "$OFFSET" ] && continue
  NEW=$(tail -c +$((OFFSET + 1)) "$MSG" | tr -d '\r')
  OFFSET=$now
  if printf '%s' "$NEW" | grep -qiE "hosting .*0\.001[0-9]|--play|join with|lobby [0-9]{12,}"; then
    LOBBY=$(printf '%s' "$NEW" | grep -oE "[0-9]{17,19}" | head -1 || true)
    say "HOST SEEN: ${LOBBY:-no id given} -- launching the served client now"
    : > "$GAMELOG"
    nohup script -q /dev/null "$APP" -- --play >> "$GAMELOG" 2>&1 &
    GPID=$!
    say "client pid $GPID; staying ${RUN_WINDOW}s"
    for _i in $(seq 1 $((RUN_WINDOW / 15))); do
      sleep 15
      kill -0 "$GPID" 2>/dev/null || { say "client exited early"; break; }
    done
    # Kill the app under `script`, not by pattern: a -f match on the app path also matches
    # the shell whose command line mentions it, which would kill the watchdog too.
    pkill -P "$GPID" 2>/dev/null; kill "$GPID" 2>/dev/null; sleep 2
    pkill -P "$GPID" 2>/dev/null; kill -9 "$GPID" 2>/dev/null
    {
      echo "# Auto-join result -- $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      echo; echo "Lobby id from his post: ${LOBBY:-none}"
      echo
      # A client that cannot join HOSTS ITS OWN WORLD instead, which looks nothing like a failure
      # in a grep summary: it is a full, working session with nobody else in it. Saying so plainly
      # matters more than the counts, because a void run reported as a failed test would send us
      # cutting a version to fix a bug that was never exercised.
      void=$(count "hosting a new one")
      over=$(count "Took the session over as host")
      moved=$(count "The host moved the party")
      if [ "$void" -gt 0 ]; then
        echo "VERDICT: **VOID** - I never reached him. My client found no open 'world' lobby and"
        echo "hosted its own, so this run proves nothing about T1b or T2. He was not hosting, or the"
        echo "lobby had closed by the time I looked. Re-run it; do not read the counts below as results."
      elif [ "$over" -gt 0 ]; then
        echo "VERDICT: **T2 PASS** - he left and I stayed: I took the session over and kept the world."
        [ "$moved" -gt 0 ] && echo "         and T1b PASS - I followed the party move without pressing anything."
      elif [ "$moved" -gt 0 ]; then
        echo "VERDICT: **T1b PASS** - the host moved the party and I followed with no input."
        echo "         T2 NOT REACHED - I never saw him leave. Did he quit mid-dungeon?"
      else
        echo "VERDICT: **INCONCLUSIVE** - I was in the session but neither the move nor the takeover"
        echo "         appeared. Either he had not walked into the trigger yet in this window, or the"
        echo "         transition/takeover did not happen. The log below is the evidence to read."
      fi
      echo; echo "Grep of MY client log:"
      for pat in "attached" "spawning player_" "No open 'world' lobby" "The host moved the party" "Took the session over as host" "took the session over: player_1"; do
        printf '  %-42s %s hit(s)\n' "$pat" "$(count "$pat")"
      done
      echo; echo "Last 30 lines of the client log:"; tail -30 "$GAMELOG" 2>/dev/null
    } > "$RESULT"
    say "run finished; result written to $RESULT"
    # Report it where the other agent will see it. A test whose result only exists on the machine
    # that ran it is a test nobody can act on, and the whole point of this joiner is that it runs
    # while no agent is awake to read its log.
    {
      echo
      echo "---"
      echo
      printf '### Castor (Mac) | %s UTC\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      printf '**AUTO-JOIN RESULT - the joiner made the run without a human on my side.** Lobby from your post: %s\n\n' "${LOBBY:-none given}"
      cat "$RESULT"
      echo
      printf '**Read it this way:** a hit on `The host moved the party` means T1b (I followed without pressing anything). A hit on `Took the session over as host` means T2 (I survived you leaving and kept the world). Zero hits where you expected one is a real failure, not a mistimed run - I was already in the session before you moved.\n'
    } >> "$COMMS_DIR/messages/from-castor.md"
    say "result also posted to from-castor.md"
    exit 0
  fi
done
say "timed out after ${TOTAL_WAIT}s with no hosting announcement; nothing launched"
