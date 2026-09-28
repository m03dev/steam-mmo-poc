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

# --- keep the compiled build identity in step ----------------------------------
# GAME_VERSION is a const inside NetworkManager.gd, because an exported .pck does
# not reliably ship res://VERSION - so it has to be written here, or the running
# game would report a version that is not the one it is.
net_mgr="$PROJECT_DIR/autoload/NetworkManager.gd"
sed -i '' -E "s/(const GAME_VERSION: String = \")[^\"]*(\")/\1$next\2/" "$net_mgr"
grep -q "const GAME_VERSION: String = \"$next\"" "$net_mgr" \
	|| { echo "could not set GAME_VERSION to $next in NetworkManager.gd" >&2; exit 1; }
echo "==> GAME_VERSION in NetworkManager.gd set to $next"

# --- build ---------------------------------------------------------------------
echo "==> exporting '$PRESET'"
"$GODOT" --headless --path "$PROJECT_DIR" --export-release "$PRESET" "$BUILD_DIR/SteamMMO.exe" >/dev/null

# --- Steam App ID --------------------------------------------------------------
# The build runs as the App ID in steam_appid.txt, and SteamManager reads the copy
# beside the executable first. Copying it into the build means the shipped file
# cannot disagree with the repo, and say so out loud when it is still Valve's
# shared test app - a build handed to other people must not be.
appid_file="$PROJECT_DIR/steam_appid.txt"
appid="$(tr -d '[:space:]' < "$appid_file" 2>/dev/null || echo '')"
cp "$appid_file" "$BUILD_DIR/steam_appid.txt"
if [ "$appid" = "480" ]; then
	echo "!! App ID 480 (Spacewar): a local test build, not something to hand out." >&2
elif [ -z "$appid" ]; then
	echo "!! steam_appid.txt is empty - the build will fall back to 480 at runtime." >&2
else
	echo "==> shipping App ID $appid"
fi

# --- package -------------------------------------------------------------------
mkdir -p "$DIST_DIR"
zip_path="$DIST_DIR/SteamMMO_$next.zip"
rm -f "$zip_path"
( cd "$BUILD_DIR" && zip -q "$zip_path" SteamMMO.exe SteamMMO.pck \
	libgodotsteam.windows.template_release.x86_64.dll steam_api64.dll steam_appid.txt )

size="$(stat -f '%z' "$zip_path")"
sha="$(shasum -a 256 "$zip_path" | cut -d' ' -f1)"
echo "==> $zip_path  ($size bytes)"

# --- macOS build ----------------------------------------------------------------
# Exported with the STANDARD (non-.NET) editor on purpose: this project is pure
# GDScript, so a mono export would bundle a .NET runtime that nothing loads. The
# engine names a bundle's innards after the project rather than the bundle, so the
# executable and the .pck BOTH have to be renamed: Godot looks for "<exe>.pck" and
# a mismatch means the app cannot find its own data ("Couldn't load project data").
MAC_GODOT="${MAC_GODOT:-$HOME/Applications/Godot.app/Contents/MacOS/Godot}"
mac_zip=""
if [ -x "$MAC_GODOT" ]; then
	echo "==> exporting 'macOS' with the standard editor"
	rm -rf "$BUILD_DIR/macos"
	mkdir -p "$BUILD_DIR/macos"
	"$MAC_GODOT" --headless --path "$PROJECT_DIR" --export-release "macOS" \
		"$BUILD_DIR/macos/SteamMMO.app" >/dev/null
	app="$BUILD_DIR/macos/SteamMMO.app"
	inner="$(find "$app/Contents/MacOS" -maxdepth 1 -type f -perm +111 2>/dev/null | head -1)"
	if [ -n "$inner" ] && [ "$(basename "$inner")" != "SteamMMO" ]; then
		inner_name="$(basename "$inner")"
		mv "$inner" "$app/Contents/MacOS/SteamMMO"
		if [ -f "$app/Contents/Resources/$inner_name.pck" ]; then
			mv "$app/Contents/Resources/$inner_name.pck" "$app/Contents/Resources/SteamMMO.pck"
		fi
		plutil -replace CFBundleExecutable -string SteamMMO "$app/Contents/Info.plist"
		plutil -replace CFBundleName -string SteamMMO "$app/Contents/Info.plist"
	fi
	cp "$appid_file" "$app/Contents/MacOS/steam_appid.txt"
	mac_zip="$DIST_DIR/SteamMMO_${next}_macos.zip"
	rm -f "$mac_zip"
	# ditto, not zip: a .app is a bundle, and plain zip loses the metadata and the
	# executable bit that make it launchable.
	ditto -c -k --sequesterRsrc --keepParent "$app" "$mac_zip"
	mac_size="$(stat -f '%z' "$mac_zip")"
	mac_sha="$(shasum -a 256 "$mac_zip" | cut -d' ' -f1)"
	echo "==> $mac_zip  ($mac_size bytes)"
else
	echo "==> no standard (non-.NET) editor at $MAC_GODOT - skipping the macOS build"
fi

# --- web build ------------------------------------------------------------------
# The itch HTML5 channel wants a FOLDER, not a zip. Threads are off in the preset,
# so the host needs no cross-origin headers to serve it.
WEB_GODOT="${WEB_GODOT:-$MAC_GODOT}"
web_dir=""
if [ -x "$WEB_GODOT" ]; then
	web_dir="$BUILD_DIR/web"
	rm -rf "$web_dir"
	mkdir -p "$web_dir"
	echo "==> exporting 'Web'"
	"$WEB_GODOT" --headless --path "$PROJECT_DIR" --export-release "Web" \
		"$web_dir/index.html" >/dev/null
	echo "==> $web_dir  ($(du -sh "$web_dir" | cut -f1))"
fi

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
	if [ -n "$mac_zip" ]; then
		cp "$mac_zip" "$drive_dir/"
		if [ "$(shasum -a 256 "$drive_dir/SteamMMO_${next}_macos.zip" | cut -d' ' -f1)" = "$mac_sha" ]; then
			echo "==> Drive: ver_control/SteamMMO_${next}_macos.zip"
		else
			echo "!! the Drive macOS copy differs from the source -- check the upload" >&2
		fi
	fi
else
	echo "==> Drive is not mounted; dist/ has the zips"
fi

# --- record --------------------------------------------------------------------
printf '%s\n' "$next" > "$VERSION_FILE"
{
	printf '## %s -- %s\n\n' "$next" "$(date '+%Y-%m-%d %H:%M')"
	printf -- '- %s\n' "$NOTE"
	printf -- '- `SteamMMO_%s.zip` -- %s bytes -- sha256 `%s` (Windows)\n' "$next" "$size" "$sha"
	if [ -n "$mac_zip" ]; then
		printf -- '- `SteamMMO_%s_macos.zip` -- %s bytes -- sha256 `%s` (macOS)\n' "$next" "$mac_size" "$mac_sha"
	fi
	if [ -n "$web_dir" ]; then
		printf -- '- `build/web/` -- %s -- Web/HTML5, built from the same tree\n' "$(du -sh "$web_dir" | cut -f1)"
	fi
	printf '\n'
} >> "$LEDGER"
echo "==> VERSION is now $next, entry appended to VERSIONS.md"
