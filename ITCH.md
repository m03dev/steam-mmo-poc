# ITCH.md — putting SteamMMO on itch.io

Everything known about the itch.io half, what has to happen, and in what order. Written so
that a fresh session can pick this up cold.

## Why itch at all

Steam has a gate in front of it: a game needs its own App ID, an App ID needs a Steamworks
partner account, and that account needs Mohamed's identity and Valve's approval. **itch.io
has no such gate** — a page can exist in minutes and a build can be live the same hour. For
a POC that friends should be able to play, itch is the shortest path from here to there.

Costs nothing to have, and it does not compete with Steam: the same Windows zip can go to
both.

## The one real obstacle — solved (desktop), with two honest limits

**Multiplayer in this game ran over Steam**, so an itch build was going to be single-player
only. That is no longer true for the **downloaded** builds: there is now a **direct-IP
transport** (plain ENet) that needs no Steam at all.

It was a small change precisely because the seam was already right — `autoload/NetworkManager.gd`
was the only file that knew what a Steam peer is:

- `NetworkManager.host_direct(port)` / `NetworkManager.join_direct(address, port)` set an
  `ENetMultiplayerPeer` on `multiplayer` instead of a `SteamMultiplayerPeer`. `var peer` is
  now typed `MultiplayerPeer` (the base of both), and the Steam-only calls take a typed
  local, so nothing above this file changed.
- Start screen: **Host Direct (IP, no Steam)** and a **Join Direct** address field. Both stay
  enabled when Steam is missing — that is their whole reason to exist.
- Headless / scripted entry, which is how two peers get tested:
  `-- --host-direct` and `-- --join-direct=192.168.1.20` (bare `--join-direct` = localhost);
  `--direct-port=N` when two instances share one machine. Default port **23460**.
- A dungeon is a *second* session found through Steam's lobby list, so it cannot exist over a
  direct link: the trigger now refuses, **keeps the session up**, and says so in the combat
  log. Direct-IP play is **world-only**.

**Verified, live:** two real game processes on this Mac, `--host-direct` and
`--join-direct=127.0.0.1` — both load the real `Main.tscn` shell, the host spawns
`player_1` and `player_<id>`, the client sees both, and **zero errors** on either side. The
Steam path was re-run afterwards to prove it still works (lobby created, host peer created,
world loaded). Unit suite: **161/161**, of which 11 are new (`tests/unit/test_direct_transport.gd`).

**No `PROTOCOL_VERSION` bump**, and this was checked rather than assumed: nothing on the wire
carries a Steam id — `scripts/` never consults one, and `autoload/NetStats.gd` already falls
back when a peer is not a `SteamMultiplayerPeer`. The transport swaps the peer object, not the
format. (Protocol stays 3.)

### The two limits to state on the page

1. **The browser build cannot do it.** A browser cannot open a raw UDP socket, so ENet cannot
   exist there. The Web build is **single-player by nature**; the start screen disables the
   direct buttons on that platform and says why. Multiplayer on itch means the **Windows /
   macOS downloads**.
2. **LAN is free; the open internet is not.** Two machines on one network connect by typing an
   address. Across the internet the host must forward port 23460 (or use a VPN) — there is no
   relay doing it for us, unlike Steam's SDR. The refusal message says this out loud.

**So be honest on the itch page**: "Multiplayer (windows/macos download): host over IP, or use
the Steam build. Browser build is a single-player preview." Never quietly ship a build that
silently cannot find other players — the friends-only lobby trap already taught that lesson.

## IT IS LIVE (2026-09-28) -- and verified end to end, not just uploaded

**<https://mo3dev.itch.io/testing>** -- public, **HTTP 200**, and the page lists
`SteamMMO_0.0011.zip`, `SteamMMO_0.0011_macos.zip` and version **0.0011** with download buttons.

The verification that matters -- **fetched back from itch and compared**, because an upload that
"succeeded" is not the same as an artefact that arrived:

| Check | Result |
| --- | --- |
| `butler fetch mo3dev/testing:windows` -> sha256 | `40d2fdf8…` == `VERSIONS.md` **MATCH** |
| `butler fetch mo3dev/testing:osx` -> sha256 | `3d11a3ae…` == `VERSIONS.md` **MATCH** |
| each channel serves | **1 file, 0 dirs** -- the zip as a blob, so butler did not unpack it |
| `unzip -Z` of the served macOS zip | `-rwxr-xr-x … Contents/MacOS/SteamMMO` -- the executable bit survived |
| the **served** macOS bundle, extracted and run | boots: `SteamMMO v0.0011`, protocol 3, exit 0 |

Two builds of 0.0011 exist per channel: #2033335/#2033336 and then #2033339/#2033340 from this
machine's push. butler reported **"Re-used 100.00% of old, added 0 B fresh data"**, which is itself
proof that both pushes carried identical bytes -- the two agents independently put the same
artefacts on the same channels.

### What the live page still lacks (all of it is Mohamed's, and none is code)

1. **The page is called "testing"** and has no description. The paste-ready text is `ITCH_PAGE.md`.
   Recommended before sharing the link: rename the title to *Steam MMO POC* and change the URL slug
   to `steam-mmo-poc` (nothing links to the old one yet).
2. **No screenshots.** Four real ones are in `agent-comms/itch-assets/` (`02_open_world.png` is the
   cover at 630x500).
3. **No Gatekeeper note**, so a Mac downloader will report a working build as broken. The line is in
   `ITCH_PAGE.md` under *System requirements*.

### The one thing still unverified

**No Windows machine has ever run 0.0011.** The zip is structurally complete (`SteamMMO.exe`,
`SteamMMO.pck`, both Steam DLLs, `steam_appid.txt`, matching exe/pck names) and the macOS sibling
boots, but "should work" is not "does". Pollux's clean-machine test is the only instrument for it.

## What Mohamed has to do now -- two minutes, and only he can

Good news first: **the page already exists.** Pollux created it and pushed both channels from
Windows; it is **`mo3dev/testing`** -- <https://mo3dev.itch.io/testing>. Two things are left:

1. **Make the page visible.** It is currently a **private draft**, so that URL 404s for
   everyone else. On itch: the project -> *Edit* -> **Visibility** -> *Public* (or *Restricted*
   while testing).
2. **Authenticate butler on THIS machine.** Credentials do not travel between machines:
   Pollux's pushes came from his Windows box and this Mac has never logged in. One command, run
   by him:

       ~/Applications/butler/butler login

   It writes `~/Library/Application Support/itch/butler_creds` -- butler's **macOS** default,
   which is *not* `~/.config/itch/` (the Linux path). `tools/itch_push.sh` checks both, and that
   matters: its first version knew only the Linux path, so it would have refused a perfectly
   valid push on this machine. For a one-off instead: an API key from itch -> *Settings* ->
   **API keys**, exported as `BUTLER_API_KEY` and revoked afterwards. I never hold either
   credential.

I cannot register accounts for him -- an account is an agreement in his name, tied to his email
and password, and me holding those would be strictly worse for him. That half is done; the two
items above are what is left.

### Why the live builds still need replacing

Both channels hold **Pollux's builds from `src_b81ca5c`**, labelled `0.1.0` (windows) and
`0.1.2` (osx). They predate the direct-IP transport and this week's fixes. Windows is confirmed
working by Mohamed; the osx channel now serves a zip that unzips to a runnable app. Pushing
`0.0011` from this machine replaces both.

### Version labels, so the page does not look like a downgrade

itch shows each build's version string, and Pollux labelled his `0.1.x` while the repo's single
source of truth (`VERSION`) says **0.0011**. Pushing under `0.0011` reads as a rollback, so say
it once in the page text: version strings now follow the repo, because a version matching the
code is the one that stops "which build is this?" confusion. From the next release on the two
move together.

## What I do once the page exists

**It is one command, and it refuses to ship anything it cannot vouch for:**

```bash
tools/itch_push.sh <itch-user> <page-slug>            # windows + osx
tools/itch_push.sh <itch-user> <page-slug> --dry-run  # print the pushes, send nothing
tools/itch_push.sh <itch-user> <page-slug> --html5    # only if the web build passes
```

What that script does, in the order that matters:

- Verifies **both zips against the sha256 in `VERSIONS.md`** before pushing, so a build
  edited by hand after release cannot quietly go up.
- Pushes `windows` and `osx` **only**. `html5` is deliberately not pushed: its menu is dead
  in a browser (see the browser section below), and a broken page is worse than no page.
  `--html5` exists, but it runs `tools/web_smoke.sh` first and **aborts** if the browser
  build fails — the flag cannot be used to ship the known-bad build by accident.
- **Pushes every zip as a blob from its own staging directory (`--no-auto-unzip`).** This is
  not tidiness. butler's default is to *unpack* a lone zip found in the source directory, and on
  the `osx` channel that strips the `.app`'s executable bit -- which is exactly why Pollux's
  first macOS push produced a download that would not open on a Mac. He found it, fixed it with
  this flag, and proved the fix by fetching the deployed build back and comparing sha256. Pushing
  the blob keeps the delivered artefact byte-identical to the file `VERSIONS.md` records, so the
  ledger means something from disk to downloader. Verified here on butler v15.31.0: without the
  flag the dry run lists the loose `SteamMMO.app/...` tree; with it, "1 files, 63.36 MiB".
- Refuses to run without butler auth, checking **both** identity paths (macOS and Linux), and
  prints the one command Mohamed has to run himself.
- Reminds you of the page text that stops testers reporting a good build as broken (the
  unsigned-macOS/Gatekeeper note), and that the same push is the update mechanism.

(the artefact is `_macos.zip`, not `_mac.zip`, and an HTML5 channel wants the **folder**,
not a zip.)

**The macOS download WILL be quarantined by Gatekeeper.** The app is unsigned, so a copy that
arrives over the internet gets flagged: testers see *"cannot be opened because the developer
cannot be verified"* or even *"it is damaged"*. Neither means the build is broken — it means
macOS does not know the author. They can right-click -> **Open** (once), or run
`xattr -dr com.apple.quarantine SteamMMO.app`. **Put this on the page**, or friends will report
the Mac build as broken and be right to.

- Channel names are permanent; `windows` / `osx` / `linux` keep the page tidy and let
  itch's app install the right one.
- A push of a new version to the same channel is the **update mechanism** — friends get a
  "new version available" in the itch app. That is the "updates land in one place" property
  that motivated this whole thread.
- Tag the build before pushing (`butler push --userversion 0.0009`), so the version shown on
  the page matches `VERSION`. Version strings in one place only.
## The browser build: it renders, but it does NOT work yet — and now we know exactly why

The best artefact itch can host would be a **click-and-play browser build** — no download, no
install, no Steam account. It is produced, and it looks perfect. It is not shippable.

**What was true before, and was too generous:** an earlier note here said the build "boots"
past the loading splash, and that the only thing left was a human glance. Both halves were
wrong, and the reason is worth writing down:

- **Headless Chrome was the wrong instrument.** It stops at the loading splash and reports
  nothing, which I mistook for a rendering limit. A **real** browser goes all the way to the
  start screen — every button drawn, `Steam: not connected` shown.
- **A web export can boot, draw its menu, and be completely inert.** The game's own errors go
  to the *browser's* console, where nothing on the developer's machine sees them. Captured, it
  is unambiguous:

      ERROR: Failed to instantiate an autoload, script 'res://autoload/SteamManager.gd'
             does not inherit from 'Node'.
      (the same for NetworkManager.gd and NetStats.gd)
      SCRIPT ERROR: Parse Error: Identifier "Steam" not declared in the current scope.
      SCRIPT ERROR: Parse Error: Could not find type "SteamMultiplayerPeer".

**Root cause.** A browser has no GodotSteam (there is no wasm32 binary) and therefore no
`Steam` global and no `SteamMultiplayerPeer` *type*. These are **parse-time** failures, not
runtime ones: the whole script is rejected before a line of it runs, so no
`Engine.has_singleton("Steam")` guard can help. The three autoloads that name Steam never
instantiate, and the menu — which talks to `NetworkManager` for every button — is dead. Only
the picture is alive. (~52 references in `NetworkManager.gd`, 7 in `NetStats.gd`,
6 in `SteamManager.gd`.)

**Check it with one command, do not trust a screenshot:**

```bash
tools/web_smoke.sh              # serves build/web, drives a real Chrome in its own
                                # profile, prints the game's console, verdicts FAIL/PASS
```

It captures only the browser window's rectangle (never the whole screen) and exits non-zero
on this exact failure. This is how the finding above was produced, and how any fix must be
confirmed.

### What it would take to fix (a real decision, for Mohamed)

| Option | Cost | Result |
| --- | --- | --- |
| **A. Web-only shims** | Small, contained: three small scripts implementing the *same public surface* (`NetworkManager.TYPE_WORLD`, `is_direct_session()`, the signals, …) and switching to them **only inside the web export**, so no desktop code changes at all. | A working single-player browser demo. Two implementations of one API to keep in step. |
| **B. Take Steam out of the parse path** | Larger, careful: move every Steam call and Steam type behind a lazily-loaded backend in the three autoloads, so they parse anywhere. | One implementation, cleaner long-term — and it touches the verified Steam path, which then needs re-testing. |
| **C. Drop the `html5` channel** | Zero. | itch = Windows + macOS downloads. Browser demo never happens. |

**Worth knowing before choosing:** even fixed, the browser build is **single-player only** —
a browser cannot open a UDP socket, so no transport can ever work there. Option A buys a
demo people can try in a tab; it does not buy multiplayer.

Push it once it passes and the slug exists:

```bash
~/Applications/butler/butler push build/web <user>/<slug>:html5 --userversion <version>
```

itch wants the **folder** for an HTML5 game, not a zip, and it must contain `index.html`.

The export recipe (unchanged, and it works — the output is complete):

```bash
cd /Users/mohamed/testing-17
mkdir -p build/web                       # Godot will NOT create this for you
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --export-release "Web" build/web/index.html
```

Result: `index.html` / `.js` / `.wasm` / `.pck`, ~45 MB, threads **off** so it needs no
special headers from itch. Templates are installed and `export_presets.cfg [preset.2]` holds
the config; see `AGENTS.md` section 9 for the details and the traps.

## Page copy

The paste-ready store text lives in **`ITCH_PAGE.md`** -- title, tagline, description, system
requirements, screenshot guidance. It is deliberately kept accurate to the shipped build: the
first draft (Pollux's, `patches/itch-page-copy.md`) named a direct-IP port of **24565** and
buttons called "Host by IP" / "Join by IP". The build's port is **23460** and the buttons are
**`Host Direct (IP, no Steam)`** / **`Join Direct`**. A store page that teaches the wrong button
name is worse than a vague one -- change `ITCH_PAGE.md` in the same commit as the UI.

Screenshots, in the order the page shows them: the start screen (Steam row **and** direct-IP
row), the open world with a wolf, the dungeon, and the dev HUD with two peers and their pings.
The game's own camera, never a mockup.

## Checklist, in order

- [x] **1. Direct-IP ENet transport** so a downloaded itch build can play multiplayer with no
      Steam at all. **Done and verified live** (two processes, no lobby, both in the world);
      161/161 unit tests pass; protocol unchanged at 3. Two limits stand: the **browser build
      stays single-player** (no UDP in a browser) and direct-IP play is **world-only** (a
      dungeon needs a Steam session). — *owner: Castor, done*
- [ ] **1b. Browser build — DECISION PARKED (Mohamed, 2026-09-28): push the downloads
      first, settle the browser later.** It exports, serves, and *renders* its menu in a real browser,
      but the menu is **inert**: three Steam-coupled autoloads fail to parse in web (see the
      section above for the console evidence). **NOT shippable as it stands.** Needs a
      decision (options A/B/C above, owner: Mohamed) and then the work (owner: Castor), and
      in either case a `tools/web_smoke.sh` pass before it goes on the page.
- [x] **2. The page exists** -- **`mo3dev/testing`**, created and first pushed by Pollux. Still
      needed from Mohamed: itch -> the project -> Edit -> **Visibility -> Public** (it is a
      private draft, so the URL 404s).
- [ ] **3. Authenticate butler on the MAC.** Pollux's credentials live on Windows, so this
      machine still cannot push. Mohamed: `~/Applications/butler/butler login` once (or
      `BUTLER_API_KEY` for a single push, revoked after). Watch the identity path -- macOS uses
      `~/Library/Application Support/itch/butler_creds`.
- [x] **4a. The push is one command and it cannot lie** -- `tools/itch_push.sh` defaults to
      `mo3dev/testing`; verifies both zips against the `VERSIONS.md` sha; pushes each as a **zip
      blob from a staging dir (`--no-auto-unzip`)** so the macOS download keeps its executable
      bit (the trap Pollux hit, and one this script's *own* first version walked into); refuses
      without auth, checking both platform paths; refuses `--html5` while the browser build is
      broken. Dry runs verified for both channels.
- [ ] **4b. Castor: push 0.0011 to replace the stale live builds** as soon as the Mac is
      authenticated, then confirm what is actually served (`butler fetch` + sha256).
- [x] **4c. Castor: page screenshots taken** -- `01_start_screen`, `02_open_world` (the cover),
      `03_dungeon`, `04_two_peers` in `dist/screenshots/` and the Drive `itch-assets/` folder.
      `tools/shot.sh` takes them from the real game; see `ITCH_PAGE.md` for what each shows and
      the exact commands.

**The macOS zip is verified the way a downloader receives it**, not just built: unzipped into
`/tmp`, the bundle carries `rwxr-xr-x` on `SteamMMO.app/Contents/MacOS/SteamMMO` inside the zip
(`unzip -Z` confirms it), and the extracted app boots -- `SteamMMO v0.0011`, protocol 3, Steam
API OK, exit 0. Pushed as a blob it therefore arrives runnable; pushed through butler's default
auto-unzip it would not.
- [ ] **7. Only then** consider Steam, which needs the App ID (`STEAM_RELEASE.md`).

Steps 1 and 2 are independent and can happen in either order — but do **not** put the page
up publicly until step 5 has passed, because a broken first impression is expensive and
this project's whole character so far has been to say what is actually true.