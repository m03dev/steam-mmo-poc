#!/usr/bin/env bash
#
# release.sh -- package the game as the next numbered version into Google Drive.
#
#   tools/release.sh "what changed"
#
# Every run steps the version by 0.0001 (0.0001, 0.0002, ...), so no build is
# ever overwritten and any copy sitting on another machine can be named back to
# the change that produced it. The zip lands in dist/ and, when Google Drive for
# Desktop is running, also in "My Drive/ver_control".
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Applications/Godot_mono.app/Contents/MacOS/Godot}"
PRESET="${PRESET:-Windows Desktop}"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
VERSION_FILE="$PROJECT_DIR/VERSION"
LEDGER="$PROJECT_DIR/VERSIONS.md"
NOTE="${1:-no note}"

# --- work out the next version -------------------------------------------------
current="$(cat "$VERSION_FILE" 2>/dev/null || echo 0.0000)"
# The step is a fixed 0.0001, so count ten-thousandths and format the number
# back: adding 0.0001 to a float drifts once enough releases have piled up.
index="$(printf '%s' "$current" | sed -E 's/^[0-9]+\.0*([0-9]+)$/\1/')"
if [ -z "$index" ]; then
	echo "VERSION holds '$current', which is not in 0.NNNN form" >&2
	exit 1
fi
next="$(printf '0.%04d' "$((index + 1))")"

echo "==> release $next  ($NOTE)"

# --- build ---------------------------------------------------------------------
echo "==> exporting '$PRESET'"
"$GODOT" --headless --path "$PROJECT_DIR" --export-release "$PRESET" "$BUILD_DIR/SteamMMO.exe" >/dev/null

# --- package -------------------------------------------------------------------
mkdir -p "$DIST_DIR"
zip_path="$DIST_DIR/SteamMMO_$next.zip"
rm -f "$zip_path"
( cd "$BUILD_DIR" && zip -q "$zip_path" SteamMMO.exe SteamMMO.pck \
	libgodotsteam.windows.template_release.x86_64.dll steam_api64.dll steam_appid.txt )

size="$(stat -f '%z' "$zip_path")"
sha="$(shasum -a 256 "$zip_path" | cut -d' ' -f1)"
echo "==> $zip_path  ($size bytes)"

# --- copy into Drive, when Drive for Desktop is mounted ------------------------
drive_root="$(find "$HOME/Library/CloudStorage" -maxdepth 1 -type d -name 'GoogleDrive-*' 2>/dev/null | head -1 || true)"
if [ -n "$drive_root" ] && [ -d "$drive_root/My Drive" ]; then
	drive_dir="$drive_root/My Drive/ver_control"
	mkdir -p "$drive_dir"
	cp "$zip_path" "$drive_dir/"
	# Drive uploads asynchronously, so compare the copy that landed.
	if [ "$(shasum -a 256 "$drive_dir/SteamMMO_$next.zip" | cut -d' ' -f1)" = "$sha" ]; then
		echo "==> Drive: ver_control/SteamMMO_$next.zip"
	else
		echo "!! the Drive copy differs from the source -- check the upload" >&2
	fi
else
	echo "==> Drive is not mounted; dist/ has the zip"
fi

# --- record --------------------------------------------------------------------
printf '%s\n' "$next" > "$VERSION_FILE"
{
	printf '## %s -- %s\n\n' "$next" "$(date '+%Y-%m-%d %H:%M')"
	printf -- '- %s\n' "$NOTE"
	printf -- '- `SteamMMO_%s.zip` -- %s bytes -- sha256 `%s`\n\n' "$next" "$size" "$sha"
} >> "$LEDGER"
echo "==> VERSION is now $next, entry appended to VERSIONS.md"
