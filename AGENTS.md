# AGENTS.md — orientation for any agent, human or AI, working on this game

**Read this file first.** It exists because chat history is not memory: sessions start
fresh and people forget. Everything a new instance needs to be useful in the first
minute is here, and the *live* state (versions, hosts, whose turn it is) is in the
shared channel, not here.

    Live state:    <Drive>/agent-comms/STATUS.md          <- read second
    The log:       <Drive>/agent-comms/messages/from-castor.md
                   <Drive>/agent-comms/messages/from-pollux.md
    Patches:       <Drive>/agent-comms/patches/*.patch
    Builds:        <Drive>/ver_control/SteamMMO_*.zip

`<Drive>` = `~/Library/CloudStorage/GoogleDrive-*/My Drive` on the Mac,
`E:\My Drive` on the Windows box.

---

## 1. What this is

A WoW-style seamless-world MMO **proof of concept** in Godot 4.7 (mono, GDScript 2.0,
static typing everywhere). Shared open world, a dungeon you walk into, quests, an
inventory, mobs with server-authoritative AI, in-game chat. Networking is **Steam P2P
over the SDR relay** — host-authoritative, no dedicated server.

- Entry scene: `ui/start_screen.tscn`. Game shell: `scenes/Main.tscn` (persistent; swaps
  `World.tscn` <-> `Dungeon.tscn` underneath itself).
- Autoloads: `SteamManager`, `NetworkManager`, `NetStats`, `WorldState`, `Chat`.
- The vendored character controller lives in `PlayerCharacter/`, `Map/`, `Arts/` and is
  **never modified**: adapt through `scenes/Player.tscn` + a wrapper script.

## 2. The two agents

Two instances work this project on two machines. **Identity is keyed on the MACHINE**,
because agent names get reused:

| | Castor | Pollux |
| --- | --- | --- |
| Machine | Mac mini M4 (macOS) | Windows |
| Godot | `/Applications/Godot_mono.app/Contents/MacOS/Godot` | `G:\Godot_v4.7-stable_mono_win64\...\exe` |
| Owns | `scripts/`, `autoload/`, `scenes/Player.tscn`, `scenes/Main.tscn`, releases | `scenes/World.tscn`, `scenes/Dungeon.tscn`, `Map/` |
| Cuts builds | **yes — Castor only** | no |

**One writer per file.** Never edit a file the other machine owns; send a patch instead.

### The loop (this is the whole protocol)

1. **Before starting:** read `STATUS.md`, then the newest entry in *both* message files.
   Do not skip this — it is how you avoid redoing work or solving a solved problem.
2. **Work** in your own tree. Commit to your own git as often as you like.
3. **Exchange changes as patches**, never as loose edits:
   `git diff > my-change.patch` into `agent-comms/patches/`, then **append a message**
   to your own message file saying what it does, how it was tested, and what you want.
4. **Castor applies patches and cuts the build** (`tools/release.sh`), then writes
   `STATUS.md` and a snapshot (`SteamMMO_src_<sha>.zip` + `project_manifest_<sha>.txt`).
5. **Snapshots supersede**: when a new one lands, delete the old one. One at a time.
6. **After finishing:** append to your message file. One decision per entry. Say exactly
   what you did, **how you verified it** ("I read it" is not verification), and what you
   need from the other side.

**There is no push between the machines.** The other party only acts when it reads the
folder. If they have not answered, they have not looked — that is not disagreement and
not failure. Never wait silently: state what you need and move on to your own next item.

### Handoff checklist — when you stop, before you leave, write down:

- [ ] What changed (`git log --oneline -3` + the sha).
- [ ] How you proved it (command run, output seen). Live evidence beats reading code.
- [ ] What you could **not** verify, and why. This is the most valuable line you write.
- [ ] The single next action, and whose move it is.
- [ ] Anything that changed the build identity (version, **protocol**).

## 3. Running and testing

```bash
G=/Applications/Godot_mono.app/Contents/MacOS/Godot      # macOS
$G --headless --path . res://tests/game_chat_two_peer.tscn -- --host      # two-peer harness
$G --headless --path . res://tests/game_chat_two_peer.tscn -- --client
```

**The unit tests: use GUT's CLI, never the in-editor runner.**

```bash
$G --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit -glog=1
```

The in-editor runner in this project is **broken in a way that lies**: every test instance
gets `gut == null`, so `add_child_autofree` fails and assertions silently pass. A probe
containing `assert_true(false)` was reported as TESTS PASSED. Verify the harness before
trusting a green run.

A tree delivered from outside (a snapshot, a copied addon) needs **one `--import` pass**
before anything resolves: `$G --headless --path . --import`.

## 4. Build identity — the rule that saves three days

- `GAME_VERSION` lives in `autoload/NetworkManager.gd`; `tools/release.sh` bumps it and
  `VERSION` together. Printed at startup, published in the lobby, compared on join.
- **`PROTOCOL_VERSION` is the contract, not the version string.** Bump it *only* when the
  set of `@rpc` methods, their signatures, **or the set of RPC-bearing nodes** changes
  (adding an autoload with an `@rpc` counts — that is why `Chat` forced 1 -> 2 -> 3).
- Two builds with the same protocol interoperate whatever the version says. A real
  mismatch prints `BUILD MISMATCH` on join instead of becoming a phantom bug later.
- **A protocol bump invalidates every older build in the field.** Announce it.

## 5. Environment gotchas that have already cost this project time

Read these before debugging something that is not broken:

- **Stale editor** — the running Godot editor keeps a cached autoload list, so its LSP
  reports `Identifier not found: WorldState/Chat/NetworkManager` for scripts that compile
  perfectly. Fresh subprocesses are fine. Focus the script editor or restart the editor.
- **`set_multiplayer_authority` defaults to `recursive = true`** — calling it on a node
  bulldozes every descendant, including nodes that pinned their own authority. This is
  why `Stats` pins *after* the player's authority is set, and why order matters.
- **A `MultiplayerSynchronizer` sends properties from ITS OWN authority**, not the
  authority of the node a property points at. Server-owned state must ride a
  synchronizer whose authority is the server; owner-owned state must not.
- **`MultiplayerSpawner.spawn()` cannot spawn twice offline** — the second call returns
  nullptr and adds nothing. Downed mobs are hidden and revived in place instead.
- **`get_tree().root.add_child(x)` inside `_ready()` fails** ("Parent node is busy setting
  up children"). Add under `self`, or `call_deferred`.
- **`change_scene_to_file()` frees the node doing the reporting** — install monitors on
  `/root`, not on the scene being replaced, or you will debug a client that "went silent".
- **The default font has no tick glyphs** — use letters for world markers ("OK"), checked
  with `has_char`.
- **macOS has no `timeout`** — use `sleep N` + `kill`. A killed process **loses buffered
  stdout**, so a clean exit is the only way to read the last lines.
- **The `[dotnet]` marker in `project.godot` is harmless — this was measured, not assumed.**
  The tree contains **zero C# files**, yet `project.godot` still carries
  `[dotnet] project/assembly_name="testing_17"`, left there by the mono editor that created
  the project. The **standard non-.NET Godot 4.7 editor opens the project with that marker
  present, with no error**: GodotSteam loads, Steam initializes, and the GUT suite runs
  **149/149**. Do not "clean up" the marker hoping to fix something, and do not assume a
  non-.NET editor needs a project change to open this game. Both editors work.
- `steam_appid.txt` is the App ID source of truth; `tools/release.sh` copies it into the
  build and shouts in red while it is still 480.

## 6. Where this is published (and where it is not)

    Source:  https://github.com/m03dev/steam-mmo-poc         (public)
    Steam:   NOT PUBLISHED - needs its own App ID, which needs a Steamworks partner account
    itch.io: NOT PUBLISHED - see ITCH.md

`STEAM_RELEASE.md` has the Steam half. `ITCH.md` has the itch half and the one
architectural obstacle to it (multiplayer is Steam-only today).

## 7. Working with Mohamed (the human)

- He is the owner and the only one who can do account-level things: Steamworks, itch.io,
  payments, anything needing identity. **Registering accounts on his behalf is not
  allowed** — say so plainly and give him the shortest possible version of the clicks.
- He may prompt you after an absence; don't assume a conversation's context survives.
  **Leave durable notes in files, not in chat.**
- Keep answers short and concrete. Lead with the answer to what was asked.
- **Money is off-limits as a topic.** Do not bring up costs, fees, prices or earnings, in
  any framing, even when a registration step involves one. Talk about the *step*
  ("register at partner.steamgames.com") and not about what it involves.
- Don't touch `Ether-Saga-Online` or the Maya plug-in repo unless he asks.
- He is not a full-time developer: prefer working code and plain explanations over
  architecture discussion, and never claim something works without a run behind it.

## 8. Definition of verified

Before you write "done":

- [ ] Unit tests pass **via the GUT CLI**, count stated.
- [ ] If it is gameplay, it ran: `run_scene` screenshot or a harness transcript. Reading
      the code is not evidence.
- [ ] If it touches networking, it ran with **two peers**.
- [ ] What you could not check is written down, with the reason.
- [ ] `STATUS.md` and your message file updated in the same session.

Claims that were *not* verified are worth more than claims that were, as long as they say
so. That is how a POC stays honest.

## 9. Editor choice, and the web build it unlocks

**Both Godot editors run this project** — verified above: standard (non-.NET) 4.7-stable
opens it, initialises Steam and passes **149/149**, exactly like the mono editor. The game
is GDScript-only, so .NET buys it nothing.

- macOS, mono (what the Ziva-managed editor uses): `/Applications/Godot_mono.app/...`
- macOS, standard (installed for web export): `~/Applications/Godot.app/...` — same
  `4.7.stable`, commit `5b4e0cb0f`
- Use `$S=~/Applications/Godot.app/Contents/MacOS/Godot` only when a step needs the
  **standard** build; every other command in this file works with either.

**Why anyone cares about the difference:** the mono editor cannot export **Web**, and a
browser build is the one itch.io artefact that needs no download, no install and no Steam
account — the fastest possible way for a friend to actually see the game.

    **The web export is set up and produces a build. Status, precisely:**

    Templates: ~/Library/Application Support/Godot/export_templates/4.7.stable  (installed;
               web_release.zip + web_nothreads_release.zip are present). The mono set stays
               separate, in 4.7.stable.mono, so the two editors do not fight over it.
    Preset:    export_presets.cfg [preset.2] = "Web", variant/thread_support=false, so the
               export uses the *nothreads* templates and needs no COOP/COEP headers from the
               host - the least fussy web build itch can serve.
    Export:    mkdir -p build/web && \
               ~/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
                 --export-release "Web" build/web/index.html
               An EMPTY custom_template/ means "use the installed templates". Godot does NOT
               create the output folder - it fails with "Target folder does not exist", so
               mkdir first. Output: index.html/.js/.wasm/.pck, ~45 MB total.

**What is verified, and what is not.** The export completes cleanly, the files are complete
and serve over HTTP, and in a real browser the build **boots**: `--screenshot` captured
Godot's own loading splash rendered from the exported wasm. What is **not** verified is the
game itself reaching the start screen — under headless Chrome the boot stops at that splash
**reproducibly** (identical frame, 36303 bytes, with or without `--use-angle=metal`, with and
without swiftshader), which is a limit of software rendering, not evidence about the build.
**Do not burn an hour on headless Chrome**; open the thing in a real browser instead (see
`ITCH.md` for the local-serve one-liner). Everything about the browser is otherwise pleasant:
the code already survives a missing Steam — `autoload/SteamManager.gd` checks
`Engine.has_singleton("Steam")` first, reports `steam_initialized(false)` and returns, and
`_process` only pumps callbacks when initialised — which is exactly what a browser is, and
why the start screen's *Play Offline* is the path that matters there.

Two honest limits, so nobody promises more than this can do:

1. **A web build cannot do multiplayer.** The Steam API does not exist in a browser. Web =
   single-player preview (world, wolves, quest, inventory). Multiplayer stays on the
   downloadable Steam build, and on the direct-IP ENet transport once that exists.
2. **The .tpz is one monolithic download** for every platform — there is no web-only
   package. It is already installed once, so this is a note, not a task.