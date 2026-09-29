# Setting up this project on a fresh machine

Everything needed to open, run, test and reason about this project from a clean
clone. Written for a collaborator (human or agent) who has never seen it.

## What this is
A proof of concept for a WoW-style MMO carried over Steam peer-to-peer: a Steam
lobby layer on top of Godot's high-level multiplayer, a host-authoritative
`MultiplayerSpawner`, and a seamless world <-> dungeon swap. No combat, no
inventory, no art of our own.

## What you need
- **Godot 4.7, .NET/mono build.** The project is GDScript-only, but the .NET
  editor is what it is developed and exported with.
- **Steam, signed in on the client** (not just the website). The game talks to the
  Steam client, not to Steam's web services.
- **Spacewar, App ID 480, in that account's library.** It is free to add. Without
  it Steam refuses to initialise for the app. There is no other app ID to
  configure: `steam_appid.txt` in this repo root contains `480`.

## Open it

On a clean checkout, **import once before anything else**:

    Godot --headless --path . --import

Without that first import the GodotSteam GDExtension is not registered (no
`.godot/extension_list.cfg` yet) and every autoload dies with
`Identifier "Steam" not declared`. This bites hardest on a `git archive`
snapshot, which ships no import cache - found the hard way by the Windows box.

Then:

    Godot --path .            # or open the project folder in the editor

## Run it
The entry scene is `res://ui/start_screen.tscn`:

    Godot --path .                                   # start screen
    Godot --path . -- --host-world                   # skip the menu, host the world
    Godot --path . -- --host-dungeon
    Godot --path . -- --offline                      # needs no Steam
    Godot --path . -- --host-direct                  # multiplayer with NO Steam: plain ENet
    Godot --path . -- --join-direct=192.168.1.20     # join that host (bare flag = localhost)

Hosting prints the lobby id. A second peer joins by typing that id into the
Lobby ID box on the start screen and pressing Join (there is no join-by-id
launch argument). Direct IP is the no-Steam alternative: *Host Direct* opens a
UDP port (printed on the start screen) and the other player types that machine's
address into *Join Direct*. LAN needs nothing set up; over the internet the host
forwards that port (default 23460, or `--direct-port=N`). Direct-IP sessions are
world-only - a dungeon is a second session found through Steam's lobby list - and
they cannot work in a Web build, where a browser has no UDP socket.

## Tests
GUT, configured by `.gutconfig.json`:

    Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit -glog=1

Read the summary line rather than a count written here, which goes stale: what
matters is `Failing Tests  0`. (At the time of writing: 161 tests, 359 asserts,
about 7 s.) Use the **CLI**, never the editor's GUT panel - in this project the
in-editor runner reports green for a test containing `assert_true(false)`.

## Two peers on one machine, no Steam
The real game, not a harness - two processes, no lobby, no Steam account needed:

    Godot --headless --path . -- --host-direct
    Godot --headless --path . -- --join-direct=127.0.0.1

Both load `res://scenes/Main.tscn`; the host spawns `player_1` and
`player_<client id>` and each side sees both. A second instance on the same
port is SHARED, not per-instance: those two commands need no flag at all,
because both use the default 23460 and the client dials the HOST's port. Only a
second, INDEPENDENT session on one machine needs a port of its own (a second host
with `--direct-port=23461`) -- and then only ITS clients pass 23461. Handing the
client above a different port from its host is the one way to make this fail
silently: it dials a port nothing is listening on. Confirmed live on 2026-09-29
after a report from the Windows side.

`res://tests/two_peer_harness.tscn` remains for a narrower, scripted ENet pair on
port 23457 (`-- --host` / `-- --client`); it exercises replication, the per-peer
spawn offsets, the world/dungeon swap and the NetStats RPC ping, but it is not the
game shell. Neither path exercises Steam's SDR relay.

## Two peers on Steam
They must be on **two different Steam accounts.** A Steam lobby is keyed by
SteamID, so two instances of one account cannot be two peers: the lobby counts a
single member and the second machine either replaces the first or fails - which
looks like a dead connection rather than an error.

## How the code fits together
- `autoload/SteamManager.gd`   - Steam init/shutdown, one callback pump per frame.
- `autoload/NetworkManager.gd` - the ONLY file that knows about Steam lobbies.
  Swapping Steam for another transport means rewriting this file alone.
- `autoload/NetStats.gd`       - ping and connection quality for the dev HUD.
- `scripts/main.gd`            - session orchestration and the level swap.
- `scripts/level.gd`           - the blockout level: spawner, spawn offsets, the
  world <-> dungeon trigger.
- `scripts/net_player.gd`      - adapter on the vendored third-person controller:
  authority from the node name, local versus remote setup, camera tuning.
- `scenes/Player.tscn`         - inherited from the vendored controller, plus the
  adapter node and the `MultiplayerSynchronizer`.
- `ui/`                        - start screen, dev HUD (F3), shared theme.

Authority comes from the node name: every spawned player is named
`player_<peer_id>` and derives `set_multiplayer_authority(peer_id)` in
`_enter_tree`, so every peer agrees with no networked handoff.

## Vendored code - leave it alone
`PlayerCharacter/`, `Map/` and `Arts/` are Jeh3no's Third Person Controller
(MIT). They are kept pristine. Adapt through `scenes/Player.tscn` and
`scripts/net_player.gd`; do not edit the vendored files, so a future asset update
stays a drop-in replacement.

## Building a release
`tools/release.sh "what changed"` exports the Windows preset, zips the five
shipped files into `dist/`, writes `VERSION`, appends to `VERSIONS.md`, and
copies the zip into the shared Drive folder when it is mounted. The version
steps by 0.0001 per change. Never overwrite a published build.

## Known wrinkles
- **Steam lobbies outlive their host.** A lobby whose host process quit keeps
  reporting members to other clients, so "the lobby exists" is not evidence that
  anybody is listening. Trust the host's log, not the lobby.
- A client already in a lobby cannot join another one: `join_lobby()` returns
  early with "Already in lobby; leave first". Restart the game to clear it.
- The world <-> dungeon swap logs transient, self-healing errors: two on the host
  and four on the client (`on_despawn_receive ... ERR_UNAUTHORIZED`). Replication
  stays correct across it. Left unfixed on purpose.
- `remove_control_from_bottom_panel` from the vendored GodotSteam editor plugin
  during a headless run is harmless.
- macOS has no `timeout` command.
