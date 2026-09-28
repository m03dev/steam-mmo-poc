# Steam MMO POC (Godot 4 + GodotSteam)

A proof-of-concept WoW-style seamless MMO transport layer built on **Steam P2P / SDR**
(App ID **480**, Spacewar) with Godot's high-level multiplayer. No combat, no inventory,
no art — just *walk a box around and see other players' boxes move*, host-authoritative.

## What it does
- **SteamManager** (autoload) — inits Steam, pumps `run_callbacks()` every frame.
- **NetworkManager** (autoload) — Steam lobbies (`lobby_type` = `world` / `dungeon`, max 8) bridged
  onto `SteamMultiplayerPeer` with the Valve relay forced on (`set_server_relay(true)`), so no
  port forwarding or NAT pain.
- **Auto-join** — on launch the game joins the first open `world` lobby, or hosts one if none
  exists. If two peers launch at the same instant, it re-checks a couple of times before hosting,
  so they don't end up in two separate lobbies.
- **Levels** — `World.tscn` (40x40) and `Dungeon.tscn` (20x20). Both use the same `level.gd`.
  The host owns a `MultiplayerSpawner` and spawns one `player_<peer_id>` per peer; each player
  derives its authority from its own name, and a `MultiplayerSynchronizer` (config stored in
  `Player.tscn`) replicates position + rotation.
- **Seamless transition** — walking into a level's `Trigger` tears the session down, rejoins the
  other lobby type, and `main.gd` swaps the level underneath the persistent UI shell.

## Running it
Both machines need Steam running and signed in, with **different accounts** (a Steam account is
routed by SteamID, so two instances of the same account collide).

- **Windows:** run `SteamMMO.exe` (keep the `.pck` and the two `.dll`s beside it).
- **Editor:** press F5.

Controls: **WASD**. Walk into the tall block at the far end of the world to enter the dungeon;
the exit block returns you.

## Verification harnesses (not shipped content)
`tests/NetProbe.tscn` and `tests/NetProbe2.tscn` prove the replication and level-swap layers over
plain ENet (no Steam needed):

```
Godot --headless --path . res://tests/NetProbe.tscn  -- --host
Godot --headless --path . res://tests/NetProbe.tscn  -- --client
```
