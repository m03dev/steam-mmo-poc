#!/usr/bin/env bash
#
# steampipe.sh -- upload the newest packaged build to a Steam branch (SteamPipe).
#
#   tools/steampipe.sh                 upload to the branch in tools/steam_alpha.env
#   tools/steampipe.sh --preview       build the upload files, print the command, upload nothing
#
# UNTESTED. I wrote this without a Steamworks account or an app to upload to, so the
# parts that talk to Steam are the one thing here I could not run. The parts that do
# not (finding the newest build, generating the VDFs, refusing to upload a dev build)
# are plain shell and can be read off the screen.
#
# One-time setup, NOT done here because it needs a password and a Steam Guard code:
#
#   steamcmd +login YOUR_STEAM_LOGIN      # then: quit
#
# Config: copy tools/steam_alpha.env.example to tools/steam_alpha.env and fill it in.
# That file is gitignored, on purpose: it names your account and your app's ids.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$PROJECT_DIR/tools/steam_alpha.env"
STEAMCMD="${STEAMCMD:-steamcmd}"
PREVIEW=0
[ "${1:-}" = "--preview" ] && PREVIEW=1

if [ ! -f "$CONFIG" ]; then
	echo "missing $CONFIG" >&2
	echo "copy tools/steam_alpha.env.example to tools/steam_alpha.env and fill it in" >&2
	exit 1
fi
# shellcheck disable=SC1090
. "$CONFIG"

: "${STEAM_APP_ID:?STEAM_APP_ID is not set in $CONFIG}"
: "${STEAM_DEPOT_ID:?STEAM_DEPOT_ID is not set in $CONFIG}"
: "${STEAM_USER:?STEAM_USER is not set in $CONFIG}"
STEAM_BRANCH="${STEAM_BRANCH:-alpha}"
STEAM_BRANCH_PASSWORD="${STEAM_BRANCH_PASSWORD:-}"

# --- refuse to upload a build that talks to somebody else's app ---------------
# The App ID the game RUNS as comes from the file shipped beside the exe, so that is
# the one to check - not this project's copy of it.
newest="$(ls -1t "$PROJECT_DIR/dist"/SteamMMO_*.zip 2>/dev/null | head -1 || true)"
if [ -z "$newest" ]; then
	echo "no dist/SteamMMO_*.zip to upload - run tools/release.sh first" >&2
	exit 1
fi
stage="$PROJECT_DIR/build/steam_upload"
rm -rf "$stage"
mkdir -p "$stage"
unzip -q "$newest" -d "$stage"

shipped_appid="$(tr -d '[:space:]' < "$stage/steam_appid.txt" 2>/dev/null || echo '')"
if [ "$shipped_appid" != "$STEAM_APP_ID" ]; then
	echo "!! $newest ships App ID '$shipped_appid' but this config targets '$STEAM_APP_ID'." >&2
	if [ "$shipped_appid" = "480" ]; then
		echo "!! That is Spacewar. Put your own App ID in steam_appid.txt and re-run" >&2
		echo "!! tools/release.sh before uploading anything to Steam." >&2
	fi
	exit 1
fi
echo "==> $(basename "$newest") ships App ID $shipped_appid"

# --- generate the SteamPipe scripts -------------------------------------------
# Two files, because SteamPipe wants two: one depot (what files go where) and one
# app build (which depots, which branch, what to call it). Written fresh from the
# config each run so they can never drift from it.
build_root="$PROJECT_DIR/build/steam_build_output"
mkdir -p "$build_root"

cat > "$stage/depot_build.vdf" <<EOF
"DepotBuildConfig"
{
	"DepotID" "$STEAM_DEPOT_ID"
	"contentroot" "$stage"
	"FileMapping"
	{
		"LocalPath" "*"
		"DepotPath" "."
		"recursive" "1"
	}
	"FileExclusion" "*.vdf"
}
EOF

cat > "$stage/app_build.vdf" <<EOF
"appbuild"
{
	"appid" "$STEAM_APP_ID"
	"desc" "$(basename "$newest" .zip)"
	"buildoutput" "$build_root"
	"contentroot" "$stage"
	"setlive" "$STEAM_BRANCH"
	"preview" "0"
	"local" "$stage/depot_build.vdf"
	"depots"
	{
		"$STEAM_DEPOT_ID" "$stage/depot_build.vdf"
	}
}
EOF

echo "==> depot $STEAM_DEPOT_ID -> branch '$STEAM_BRANCH' (app $STEAM_APP_ID)"
if [ -n "$STEAM_BRANCH_PASSWORD" ]; then
	# SteamPipe takes the password on the app-build command line, not in the VDF.
	echo "==> branch is password protected"
	pw_arg="+password $STEAM_BRANCH_PASSWORD"
else
	pw_arg=""
fi

if [ "$PREVIEW" = 1 ]; then
	echo "==> --preview: not uploading. The command would be:"
	echo "    $STEAMCMD +login $STEAM_USER +run_app_build \"$stage/app_build.vdf\" $pw_arg +quit"
	exit 0
fi

if ! command -v "$STEAMCMD" >/dev/null 2>&1; then
	echo "steamcmd not found. Install it, or set STEAMCMD=/path/to/steamcmd." >&2
	exit 1
fi

# shellcheck disable=SC2086
"$STEAMCMD" +login "$STEAM_USER" +run_app_build "$stage/app_build.vdf" $pw_arg +quit

echo "==> uploaded. On the Steamworks 'Builds' page, set the build live on branch '$STEAM_BRANCH'."
echo "==> Players on that branch get it on their next Steam check."