# Steam MMO POC (Godot 4 + GodotSteam)

A WoW-style seamless-world MMO proof of concept: a shared open world, a private dungeon you
walk into, quests, inventory, mobs that fight back, and in-game chat — over **Steam P2P / SDR**
with Godot's high-level multiplayer. Host-authoritative, no dedicated server.

## Where to get it

| | |
| --- | --- |
| **Source** | <https://github.com/m03dev/steam-mmo-poc> — public, `main` branch |
| **Steam** | **not published.** A Steam release needs its own App ID, which needs a Steamworks partner account — see `STEAM_RELEASE.md` |
| **itch.io** | **LIVE** — <https://mo3dev.itch.io/testing> (Windows + macOS, version 0.0011). The page still needs its description, screenshots and Gatekeeper note pasted in; see `ITCH_PAGE.md` |
| **Version** | `0.0009`, netcode protocol `3` |

**The one blocker, stated plainly:** the game talks to Steam App ID `480` (Spacewar), Valve's
shared test app. That is perfect for two developers testing and **is not ours to distribute**, so
nothing can be handed out publicly until the game has its own App ID. Everything else is built and
tested; the App ID itself is a one-line file change (`steam_appid.txt`), gated on that account.

## What it does

- **SteamManager** (autoload) — inits Steam (App ID resolved from `--appid=N` → `steam_appid.txt`
  → dev default), pumps `run_callbacks()` every frame, and tears the peer down before
  `steamShutdown()` so exit does not segfault.
- **NetworkManager** (autoload) — Steam lobbies (`lobby_type` = `world` / `dungeon`, max 8) bridged
  onto `SteamMultiplayerPeer` with the Valve relay forced on (`set_server_relay(true)`): no port
  forwarding, no NAT pain. Public on the shared dev App ID, **friends-only** once the build is on
  its own App ID.
- **Direct IP, without Steam** — the same game over plain **ENet**, for builds that have no Steam:
  *Host Direct (IP, no Steam)* and a *Join Direct* address field on the start screen, or
  `--host-direct` / `--join-direct=ADDR` (`--direct-port=N` to pick the port; default 23460). LAN
  needs nothing set up; across the internet the host forwards that port. This is the transport an
  itch.io download uses. **No protocol change** — it swaps the peer object, so the two transports
  interoperate. Two limits: direct-IP play is **world-only** (a dungeon is a second session found
  through Steam's lobby list, so the trigger refuses and says why), and it cannot work in the
  **Web build**, where a browser cannot open a UDP socket.
- **Invites** — Steam draws its own friends list (`invite_friends()`); rich presence publishes
  `connect = +connect_lobby <id>`, which is what puts *Join Game* in a friend's list, and launching
  with `+connect_lobby <id>` (how Steam starts the game when a friend clicks Join while it is
  closed) joins that lobby directly.
- **Auto-join** — on launch the game joins the first open `world` lobby, or hosts one if none
  exists, re-checking a couple of times so two peers launching at the same instant do not end up in
  two separate lobbies. Note: Steam's lobby list returns **public** lobbies only, so a friends-only
  session is reachable by invite or lobby id, not by this search.
- **Levels** — `World.tscn` (40x40) and `Dungeon.tscn` (20x20), both using the same `level.gd`. The
  host owns a `MultiplayerSpawner` and spawns one `player_<peer_id>` per peer; each player derives
  its authority from its own name, and a `MultiplayerSynchronizer` replicates position + rotation.
- **Seamless transition** — walking into a level's `Trigger` tears the session down, rejoins the
  other lobby type, and `main.gd` swaps the level under the persistent UI shell.
- **Combat** — `scripts/enemy.gd` runs AI on the server only (idle → aggro → chase → swing on a
  cooldown, with a leash and an evade timer), `scripts/health.gd` is one Hittable component for
  players and mobs, and a swing is a *request* the server re-validates for owner, distance and
  rate. Mobs are downed rather than despawned, because health replicates.
- **Quests and inventory** — `player_progress.gd` holds the rules (pure), `player_state.gd` is the
  network facade with one replicated `net_state` dictionary, `interactable.gd` and its subclasses
  are the world's interactables, and the HUD owns no state.
- **WorldState** (autoload) — entity registry, world clock, world timers and a broadcast combat
  log, so systems stop searching the tree and stop inventing their own clocks.
- **Chat** (autoload, contributed by the Windows-side agent) — one channel over `@rpc`, with the
  speaker id taken from the transport so no peer can speak as another.

### Replication, in one paragraph

Godot sends a `MultiplayerSynchronizer`'s properties from **that synchronizer's own authority**. A
player node is owned by its player (that is what lets it move itself), which means putting
server-owned state in the same synchronizer would make the owning client the sender for the
server's values — the authoritative copy would be clobbered by the peer it is meant to be
authoritative over. The split is therefore deliberate: position and rotation ride the owner's
synchronizer; `Stats:net_state` and `Health:current` ride a second one, under `Stats`, whose
authority is pinned to the server. `tests/unit/test_replication_wiring.gd` pins that split so it
cannot silently collapse back.

## Running it

Both machines need Steam running and signed in, with **different accounts** (a Steam account is
routed by SteamID, so two instances of the same account collide).

- **Windows:** run `SteamMMO.exe` (keep the `.pck` and the two `.dll`s beside it).
- **Editor:** press F5.
- **Offline** (no Steam at all): the start screen's *Play Offline* runs the whole single-player
  loop, mobs and quests included.
- **Multiplayer without Steam:** one player presses *Host Direct* (it shows the port it opened),
  the other types that machine's address into *Join Direct*. On one machine, or for testing,
  two instances can run at once — the second needs `--direct-port=23461` so they do not fight
  over the port:

  ```bash
  Godot --path . -- --host-direct
  Godot --path . -- --join-direct=127.0.0.1
  ```

Controls: **WASD** to move, **F** attack, **E** interact, **I** inventory, **Enter** chat, **F3**
dev overlay. Walk into the tall block at the far end of the world to enter the dungeon; the exit
block returns you.

## Tests

GUT's own CLI. Do **not** trust the in-editor runner in this project: every test instance there
gets `gut == null`, so `add_child_autofree` fails and assertions silently "pass" (a probe
containing `assert_true(false)` was reported as passing).

```
Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit -glog=1
```

Currently **14 scripts, 161 tests, 359 asserts, ~7s.**

## Verification harnesses (not shipped content)

Two-peer harnesses over plain ENet (no Steam needed). They drive the **real** game, not a stub:

```
# the real game shell plus chat, on both peers
Godot --headless --path . res://tests/game_chat_two_peer.tscn -- --host
Godot --headless --path . res://tests/game_chat_two_peer.tscn -- --client
```

Also `tests/two_peer_harness.tscn` (replication + level swap) and `tests/chat_harness.tscn`
(chat alone).

## Publishing

`tools/release.sh "what changed"` cuts one numbered release: a Windows zip, a macOS zip and
the web folder, all from the same tree, recorded in `VERSIONS.md`, with both zips copied into
Google Drive and verified by sha256.

- **itch.io (downloads):** `tools/itch_push.sh <itch-user> <page-slug>` pushes the Windows and
  macOS builds. It verifies each artefact against the `VERSIONS.md` ledger before sending, and
  it will not push the browser build at all while that build's menu is dead (below). The
  macOS build is unsigned, so the page must tell people about Gatekeeper or they will report
  a good build as broken.
- **Multiplayer in those downloads:** Steam *or* direct IP. A build with no Steam can still
  host and join — one player presses *Host Direct*, the other types their address (LAN works
  as-is; across the internet the host forwards port 23460). No protocol difference: the two
  transports interoperate.
- **The browser build: produced, and knowingly NOT shippable yet.** It exports and renders its
  start screen in a real browser, but every button is inert: a browser has no GodotSteam, so
  the `Steam` global and `SteamMultiplayerPeer` type do not exist, and the three autoloads that
  name them fail to **parse** — before any of their runtime guards can run. `tools/web_smoke.sh`
  drives a real browser and reports the game's own console, so this is one command to check
  rather than a screenshot to squint at. Even once fixed it is single-player only: a browser
  cannot open a UDP socket. `ITCH.md` weighs the three ways to fix it.
- **Steam:** `STEAM_RELEASE.md` covers the Steamworks side — the App ID, the playtest shape —
  and `tools/steampipe.sh` uploads a build.

## Layout

    autoload/{SteamManager,NetworkManager,NetStats,WorldState,Chat}.gd
    scripts/{main,level,net_player,player_state,player_progress,player_combat,
             health,enemy,interactable,quest_giver,item_pickup,player_interactor,
             item_database,quest_def,quest_database}.gd
    scenes/{Main,World,Dungeon,Player,Enemy}.tscn
    ui/{start_screen,dev_hud,quest_tracker,inventory_panel,combat_log,chat_box}.*
    tests/unit/*.gd            GUT unit tests
    tests/*_harness.*          two-peer ENet harnesses (dev only)
    tools/{release.sh,steampipe.sh}
    STEAM_RELEASE.md           the Steam half, which needs a human
    VERSIONS.md                the release ledger
