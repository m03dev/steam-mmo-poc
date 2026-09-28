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

## The one real obstacle

**Multiplayer in this game runs over Steam.** So an itch build today is **single-player
only** — a friend downloads it, walks around, fights wolves, does the quest, but cannot see
anyone else. That is a property of the transport we chose, not of itch.

There is a clean fix, and it is already proven to be possible:

- `autoload/NetworkManager.gd` is the **only** file that knows what a Steam peer is.
- `tests/game_chat_two_peer.gd` already runs the **entire real game** — server, spawner,
  synchronizers, chat — over plain **ENet**, with no Steam in the process.

So a third transport ("host by IP / join by IP") is a matter of adding a sibling path in
that one file plus a couple of fields on the start screen. It is a **new RPC-bearing code
path only if it changes the wire format** — it does not; it swaps the peer object — so it
should *not* need a `PROTOCOL_VERSION` bump. Verify that claim before deciding.

**Until that exists, be honest on the itch page**: "single-player preview; multiplayer
needs the Steam build." Never quietly ship a build that silently cannot find other players
— the friends-only lobby trap already taught that lesson.

Status: **not started.** It is the first item in the itch plan below.

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
# versioned, already produced by tools/release.sh
butler push dist/SteamMMO_<version>.zip <user>/steam-mmo-poc:windows
butler push dist/SteamMMO_<version>_mac.zip  <user>/steam-mmo-poc:osx
```

- Channel names are permanent; `windows` / `osx` / `linux` keep the page tidy and let
  itch's app install the right one.
- A push of a new version to the same channel is the **update mechanism** — friends get a
  "new version available" in the itch app. That is the "updates land in one place" property
  that motivated this whole thread.
- Tag the build before pushing (`butler push --userversion 0.0009`), so the version shown on
  the page matches `VERSION`. Version strings in one place only.
## The browser build: built, and one step short of proven

The best artefact itch can host is a **click-and-play browser build** — no download, no
install, no Steam account. That is now produced:

```bash
cd /Users/mohamed/testing-17
mkdir -p build/web                       # Godot will NOT create this for you
~/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  --export-release "Web" build/web/index.html
```

Result: `index.html` / `.js` / `.wasm` / `.pck`, ~45 MB, threads **off** so it needs no
special headers from itch. Templates are installed and `export_presets.cfg [preset.2]` holds
the config; see `AGENTS.md` section 9 for the details and the traps.

**Verified:** the export completes; the files are complete and serve over HTTP; and in a real
browser the build **boots** — a capture of the running page shows Godot's loading splash
drawn from the exported wasm.

**Not verified, and said out loud:** that the game gets *past* boot to the start screen. Under
headless Chrome it stops at the splash reproducibly, whichever renderer is forced — a
software-rendering limit, not a verdict on the build. So the first real test is a human
opening it once, which takes ten seconds:

```bash
# serve it, then open the URL in any real browser
cd /Users/mohamed/testing-17/build/web && python3 -m http.server 8123
open http://localhost:8123/
```

Expect: the start screen, then **Play Offline** (there is no Steam in a browser — the code
handles that by design, `autoload/SteamManager.gd` checks for the Steam singleton first).

Push it to the page once the slug exists:

```bash
~/Applications/butler/butler push build/web <user>/<slug>:html5 --userversion 0.0009
```

itch wants the **folder** for an HTML5 game, not a zip, and it must contain `index.html`.

## Page copy (draft, for review — a first sketch, not final)

    Title:    Steam MMO POC
    Tagline:  A seamless-world MMO prototype: shared world, a dungeon, quests and combat.
    Tags:     multiplayer, mmo, prototyped, godot, low-poly

    A proof of concept for a WoW-style seamless world, built in Godot 4 over Steam's
    peer-to-peer relay: walk out of a shared open world into a private dungeon and back
    without a loading screen; kill wolves, loot pelts, finish a quest, chat with whoever
    else is online.

    This is a prototype, not a game: the world is blockout geometry, there is no art
    pass, and things will break. Single-player works in this build; multiplayer runs in
    the Steam build because it currently uses Steam to find and connect players.

Screenshots: take them with `run_scene` (the game's own camera is nicer than a mockup) —
world with a wolf, a dungeon, the quest tracker as it ticks up, the chat box with a real
line. itch shows the first four on the page, so the first one should be the wide world shot.

## Checklist, in order

- [ ] **1. Direct-IP ENet transport** so an itch build can play multiplayer (prerequisite
      for the page saying "multiplayer" at all). — *owner: Castor, not started*
- [x] **1b. Browser build** — exported, files complete, boots in a browser. **One human
      check left**: open it once in a real browser and confirm it reaches the start screen
      and plays offline (see the section above). — *owner: Mohamed, 10 seconds*
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