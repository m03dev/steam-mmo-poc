#!/usr/bin/env bash
#
# sync_check.sh -- make "we are on the same build" a FACT instead of a claim.
#
# WHY THIS EXISTS
#   Two agents coordinating through chat messages lost a session to a question that one
#   command answers: are we actually running the same thing? One side hosted a tree that
#   was a commit ahead of the build on itch, and the version string could not tell them
#   apart. Every joint test from now on starts by pasting the STATE line this prints.
#
# USAGE
#   tools/sync_check.sh                 # the full picture, then one pasteable STATE line
#   tools/sync_check.sh compare <sha>   # is the other agent's sha the same as mine?
#
# The STATE line is the protocol. Paste it into the channel before a shared test; a test
# is only valid when both sides' lines agree on sha + version + protocol, or when the
# difference is stated out loud on purpose.

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

AGENT="${AGENT:-castor}"
sha=$(git rev-parse --short HEAD 2>/dev/null || echo no-git)
dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
ver=$(cat VERSION 2>/dev/null || echo "?")
game=$(grep -aoE 'GAME_VERSION[^=]*= *"[^"]*"' autoload/NetworkManager.gd | head -1 | sed 's/.*"\(.*\)"/\1/')
proto=$(grep -aoE 'PROTOCOL_VERSION[^=]*= *[0-9]+' autoload/NetworkManager.gd | head -1 | grep -oE '[0-9]+$')

if [ "${1:-}" = "compare" ]; then
	other="${2:-}"
	if [ -z "$other" ]; then echo "usage: $0 compare <sha>" >&2; exit 2; fi
	if [ "$other" = "$sha" ]; then
		echo "MATCH   both on $sha -- a shared test is valid"
		exit 0
	fi
	echo "MISMATCH  mine=$sha  theirs=$other"
	echo "  Do not run a shared test until this is settled. Say which one is the artifact."
	exit 1
fi

echo "agent      $AGENT"
echo "commit     $sha  (uncommitted files: $dirty)"
echo "version    VERSION=$ver  GAME_VERSION=$game"
echo "protocol   $proto"
if [ -s VERSIONS.md ]; then
	echo "releases   (ledger tail)"
	tail -4 VERSIONS.md | sed 's/^/  /'
fi
if [ "$dirty" != "0" ]; then
	echo
	echo "NOTE: uncommitted files present -- if you are testing, say which artifact is running."
fi
echo
echo "STATE agent=$AGENT sha=$sha ver=$game protocol=$proto dirty=$dirty"
