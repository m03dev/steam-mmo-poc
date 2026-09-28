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

## What Mohamed has to do (about two minutes, and only he can)

I cannot register accounts for him — an account is a legal agreement in his name, tied to
his email and password, and me holding those credentials would be strictly worse for him.
So, the shortest possible version:

1. Go to **https://itch.io/register** — pick a username, email, password. Confirm the email.
2. Open **https://itch.io/game/new** and fill in a title (suggested: *Steam MMO POC*),
   and the **URL slug** (suggested: `steam-mmo-poc`). Save it. It does not have to be good
   yet; it can be edited forever, and it can stay hidden until we want it seen.
3. Decide visibility: **Draft / Restricted** while testing, **Public** when ready.

That is the whole account half. He does **not** need to know anything about uploading.

### Then, to let me upload builds (one of two options)

**`butler` is already installed** — `~/Applications/butler/butler`, v15.31.0. Not on `PATH`;
call it by that path, or add `~/Applications/butler` to `PATH`. Note the download host:
`broth.itch.ovh` **does not resolve** from this machine, use **`broth.itch.zone`**
(`https://broth.itch.zone/butler/darwin-amd64/LATEST/archive/default`, a redirect). There is
no Homebrew here.

So the only thing still missing is **auth**, one of:

**Option A — preferred, and Mohamed never hands over a key.** He runs this once, himself:

    ~/Applications/butler/butler login

It stores a credential in `~/.config/itch/butler_creds` (currently absent) and buttons this
machine to his account. I then push builds without ever holding a key.

**Option B** — he creates an API key in itch's settings and passes it to me; butler reads it
from `BUTLER_API_KEY` for a single push. Faster, worse hygiene: the key is account-wide and
should be revoked afterwards.

## What I do once the page exists

```bash
# all three artefacts come from ONE `tools/release.sh` run
~/Applications/butler/butler push dist/SteamMMO_<version>.zip       <user>/<slug>:windows --userversion <version>
~/Applications/butler/butler push dist/SteamMMO_<version>_macos.zip <user>/<slug>:osx     --userversion <version>
~/Applications/butler/butler push build/web                         <user>/<slug>:html5   --userversion <version>
```

(Note the artefact is `_macos.zip`, not `_mac.zip`, and the HTML5 channel wants the
**folder**, not a zip.)

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

## Page copy (draft, for review — a first sketch, not final)

    Title:    Steam MMO POC
    Tagline:  A seamless-world MMO prototype: shared world, a dungeon, quests and combat.
    Tags:     multiplayer, mmo, prototyped, godot, low-poly

    A proof of concept for a WoW-style seamless world, built in Godot 4 over Steam's
    peer-to-peer relay: walk out of a shared open world into a private dungeon and back
    without a loading screen; kill wolves, loot pelts, finish a quest, chat with whoever
    else is online.

    This is a prototype, not a game: the world is blockout geometry, there is no art
    pass, and things will break. In the windows/macos download you can host over your
    own IP and have a friend join (same network: just the address; across the internet:
    port 23460 forwarded), or play the Steam build. The browser build below is a
    single-player preview -- a browser cannot open the kind of socket this game uses.

Screenshots: take them with `run_scene` (the game's own camera is nicer than a mockup) —
world with a wolf, a dungeon, the quest tracker as it ticks up, the chat box with a real
line. itch shows the first four on the page, so the first one should be the wide world shot.

## Checklist, in order

- [x] **1. Direct-IP ENet transport** so a downloaded itch build can play multiplayer with no
      Steam at all. **Done and verified live** (two processes, no lobby, both in the world);
      161/161 unit tests pass; protocol unchanged at 3. Two limits stand: the **browser build
      stays single-player** (no UDP in a browser) and direct-IP play is **world-only** (a
      dungeon needs a Steam session). — *owner: Castor, done*
- [ ] **1b. Browser build** — it exports, serves, and *renders* its menu in a real browser,
      but the menu is **inert**: three Steam-coupled autoloads fail to parse in web (see the
      section above for the console evidence). **NOT shippable as it stands.** Needs a
      decision (options A/B/C above, owner: Mohamed) and then the work (owner: Castor), and
      in either case a `tools/web_smoke.sh` pass before it goes on the page.
- [x] **2. The account exists** — Mohamed has one. Still needed from him: the **username**
      and the **page slug**, so a push has a target. (Page: <https://itch.io/game/new>.)
- [ ] **3. Get `butler` working.** Installed: `~/Applications/butler/butler` v15.31.0 (see the
      correction about `broth.itch.zone` above). What is still missing is **auth** — either
      Mohamed runs `butler login` once, or he hands over an API key.
- [ ] **4. Castor: push the first build** and take the screenshots.
- [ ] **5. Verify the download runs on a machine that has never seen this project** — the
      only honest test of a distributable. Windows build on Pollux's box is the obvious
      candidate; he is already on the other side of the channel.
- [ ] **6. Both: write it into `README.md`** ("Where to get it" table) and `STATUS.md`.
- [ ] **7. Only then** consider Steam, which needs the App ID (`STEAM_RELEASE.md`).

Steps 1 and 2 are independent and can happen in either order — but do **not** put the page
up publicly until step 5 has passed, because a broken first impression is expensive and
this project's whole character so far has been to say what is actually true.