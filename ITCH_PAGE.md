# ITCH_PAGE.md — paste-ready store page text

Text for the itch.io page, kept accurate to **what the build actually does**. Pollux drafted
this from his spec (`direct-ip-enet-transport.md`); two things in that draft did not match the
build that shipped, and both are fixed here:

- the default direct-IP port is **23460**, not 24565 (that was the spec's placeholder);
- the start-screen buttons are **`Host Direct (IP, no Steam)`** / **`Join Direct`**, not
  "Host by IP" / "Join by IP".

If you change the UI or the port, change them here in the same commit — a store page that
teaches the wrong button name is worse than a vague one.

Everything in the boxes below is literal paste material.

---

## Title

```
Steam MMO POC
```

## Short description (tagline, ~140 chars)

```
A tiny Godot 4 co-op sandbox: host an open world, bring a friend over Steam or plain IP, and clear the dungeon together.
```

## Classification

- **Kind of project:** Game
- **Release status:** In development (prototype)
- **Pricing:** No payments (free)
- **Genre:** Action / Adventure
- **Tags:** `multiplayer`, `co-op`, `godot`, `3d`, `mmo`, `prototype`, `online-co-op`, `pve`

---

## Description (page body)

```markdown
**Steam MMO POC** is a small, honest proof of concept: a host-authoritative Godot 4
multiplayer sandbox. It exists to answer one question — *can two players share one living
world, fight the same mobs, and move between an open world and a dungeon, with the network
getting in nobody's way?*

It can. This build is what that looks like.

### What's in it

- **A shared open world.** One player hosts; they own the world and the mobs. Everyone else
  joins and sees the same wolves, the same loot, the same drops.
- **Two ways to connect**
  - **Steam** — host or join through a Steam lobby, which uses Steam's relay, so it crosses
    NATs with no port forwarding.
  - **Direct IP** — host on a UDP port and join by address. **No Steam account or Steam
    install needed**, which is the whole point of shipping here.
- **A dungeon run.** Step into the trigger and the whole party moves from the open world into
  the dungeon and back, together.
- **Real MMO-shaped systems, in miniature.** Host-authoritative spawning, entity state
  replication, a combat and health loop, a quest from an NPC, an inventory, and in-game chat
  — all replicated between peers.
- **A dev HUD** (F3) so you can *see* the network: your peer id, per-peer ping, replication
  activity. This is a prototype and it wears that on its sleeve.

### How to play

1. Download the build for your platform and unzip it.
2. One player starts a world: press **Host New World** (or **PLAY**, which also opens a Steam
   lobby for friends).
3. Everyone else connects:
   - **Over Steam:** press **PLAY**, or paste a **Lobby ID** and press **Join Lobby**.
   - **Without Steam:** the host presses **Host Direct (IP, no Steam)** and tells you their
     address. You type it into the address box and press **Join Direct**. Leave the box empty
     to join the same machine. Both sides use **port 23460** — it works on a LAN as-is, and
     across the internet the host forwards that UDP port.
4. Move with WASD, look with the mouse, go find the wolves. Walk into the glowing trigger at
   the far edge of the world to enter the dungeon.

Playing by yourself? **Play Offline (no Steam)** loads the world with no networking at all.

### Controls

- **WASD** — move, **Space** — jump, **Shift** — run
- **Mouse** — look, **Wheel** — zoom
- **E** — interact (talk to the trader, pick things up)
- **F** — attack
- **I** — inventory, **Enter** — chat
- **Ctrl / Esc** — release the mouse cursor
- **F3** — dev HUD

### Two honest limits

- **Dungeon transitions need Steam.** A dungeon is a second session, and the game finds it
  through Steam's lobby list. In a direct-IP session the trigger politely declines and says
  so in the log; direct-IP play is the open world. Everything else — combat, loot, the quest,
  chat — works identically.
- **The host is the authority.** Two players is what has been tested end to end, not a crowd.

### A note on the name

It is called "Steam MMO POC" because that is exactly what it is: a proof of concept, built to
prototype the *shape* of a small MMO, using Steam (and now plain IP) as transport. It is not
an MMO, and it is not finished — that is the point. Say hello to a friend, kill a wolf, and
watch the ping numbers.

### Built with

Godot Engine 4 · GodotSteam (GDExtension) · GDScript (no C#, no .NET)
```

---

## System requirements

```markdown
Windows / macOS — 64-bit, a GPU capable of Vulkan (or D3D12 on Windows).

Steam is optional: multiplayer works over a Steam lobby, or over plain IP with no Steam
account at all (the host needs UDP port 23460 reachable — LAN as-is, or forwarded for wider
internet play).

macOS note: the app is unsigned, so on first launch macOS may refuse to open it. Either
right-click the app and choose Open, or run:
    xattr -dr com.apple.quarantine SteamMMO.app
```

## Cover and screenshots

**Taken** (in `dist/screenshots/`, also in the Drive `agent-comms/itch-assets/` folder —
`dist/screenshots/` is gitignored, so the Drive copy is the one to upload from):

| File | What it shows | Use as |
| --- | --- | --- |
| `01_start_screen.png` | the start screen: PLAY / Host New World / Host Dungeon / Auto-Join Dungeon / Play Offline (no Steam), the Steam lobby row, **and** the `Host Direct (IP, no Steam)` + `Join Direct` row | screenshot 1 |
| `02_open_world.png` | the open world: a Forest Wolf mid-attack, the combat log filling in, HP down to 55/100, the quest tracker, chat, dev HUD | **cover** (630×500) or screenshot 2 |
| `03_dungeon.png` | the dungeon level, HUD reading `LOBBY dungeon … 1/8` | screenshot 3 |
| `04_two_peers.png` | **two live peers side by side** — host window (`HOST (DIRECT)`, `1 client(s) worst 13 ms`, peer row `player_324528183  13 ms`) and client window (`CLIENT (DIRECT)`, `to host 15 ms`), each showing both characters and both name tags | screenshot 4, and the honest answer to "does multiplayer actually work?" |

Every one of them is a real run of the real game, not a mockup, and none is staged: the wolf
attacking in shot 2 and the downed-and-revived player in shot 4 happened on their own.

**Retaking them** (needs a display; it drives the real game):

```bash
tools/shot.sh --out dist/screenshots/01_start_screen.png --wait 8
tools/shot.sh --out dist/screenshots/02_open_world.png --wait 10 -- --offline
tools/shot.sh --out dist/screenshots/03_dungeon.png    --wait 12 -- --host-dungeon
# the two-peer shot: two windows side by side, one image
tools/shot.sh --keep --pos 0,0   --size 900x506 --wait 12 -- --host-direct
tools/shot.sh --keep --pos 920,0 --size 900x506 --wait 16 -- --join-direct=127.0.0.1
screencapture -x -R 0,60,1820,506 dist/screenshots/04_two_peers.png
tools/shot.sh --kill-all
```

The `0,60` offset is the window's client area (macOS menu bar + title bar), measured rather
than guessed — see the note at the top of `tools/shot.sh`.

Original guidance, for a future art pass: the cover wants the character with the dev HUD and a
`player_1` name tag visible, because that reads instantly as "networked Godot game".

## Limitation to state (or leave implied)

- **No browser build is offered.** The Steam transport is a native extension with no web
  target, and a browser cannot open a UDP socket, so a web build could never be multiplayer.