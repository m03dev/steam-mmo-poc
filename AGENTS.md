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

There is also a **direct-IP transport** (plain ENet, no Steam at all) for builds that have
no Steam: `NetworkManager.host_direct()` / `join_direct()`, the start screen's two direct
controls, and `--host-direct` / `--join-direct=ADDR` / `--direct-port=N`. It is the same
game, one swapped peer object — **no wire-format change, no protocol bump**. It is
**world-only** (a dungeon is a second session found via Steam's lobby list) and cannot
exist in a browser build (no raw UDP there). `NetworkManager.gd` is still the only file
that knows which transport is in use.

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

**Two real peers on ONE machine, with no Steam, is now the cheapest end-to-end check** — and
it is the only way a single agent can watch a host and a client at once, since two processes
on one Mac share one Steam account and therefore cannot be two Steam peers:

```bash
$G --headless --path . -- --host-direct                    > /tmp/h.log 2>&1 &
$G --headless --path . -- --join-direct=127.0.0.1          > /tmp/c.log 2>&1 &
# host: "Hosting a DIRECT session on UDP 23460 (no Steam). My peer id: 1."
# client: "Dialling a DIRECT session at 127.0.0.1:23460 ..." then "Connected to host."
# both: "[Level/world] ready ..." and the host spawns player_1 and player_<client id>
```

`--direct-port=N` lets a second instance register in the process list next to a host already
on 23460. Read both logs and check `grep -cE '^ERROR' ` is **0** — a stray engine error is how
the `_ready`-time scene-swap bug was caught (see section 5). This runs the real `Main.tscn`,
not a harness, so it exercises the actual spawner, synchronizers and chat.

**The unit tests: use GUT's CLI, never the in-editor runner.**

```bash
$G --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit -glog=1
```

The in-editor runner in this project is **broken in a way that lies**: every test instance
gets `gut == null`, so `add_child_autofree` fails and assertions silently pass. A probe
containing `assert_true(false)` was reported as TESTS PASSED. Verify the harness before
trusting a green run.

Two GUT traps that cost real time here:

- `assert_signal_emitted_with_parameters()`'s **4th argument is `index`, an int** — a message
  string there is compared as an index and errors *inside GUT*, not in your test.
- GUT **fails a test on any engine error or `push_error`** raised during it. So a test that
  legitimately creates a peer (a direct dial) must close it **before the test ends**, or its
  asynchronous failure report surfaces during a later test. Use `push_warning`, not
  `push_error`, for ordinary user-input refusals.

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
- **`change_scene_to_file()` also removes the current scene IMMEDIATELY**, so calling it
  from `_ready()` errors with *"Parent node is busy adding/removing children"*. This hid
  for weeks because the Steam path only ever reaches its handover through a signal that
  arrives a frame later; a **direct host** and **`--offline`** hit it head-on. The start
  screen now defers the call (`change_scene_to_file.call_deferred(...)`). If you add a
  session path that reports **synchronously**, expect this class of bug — and run the game
  once headless and `grep -c '^ERROR'`.
- **The default font has no tick glyphs** — use letters for world markers ("OK"), checked
  with `has_char`.
- **macOS has no `timeout`** — use `sleep N` + `kill`. A killed process **loses buffered
  stdout**, so a clean exit is the only way to read the last lines.
- **macOS export: the bundle's innards are named after the PROJECT, not the bundle.** A
  `SteamMMO.app` comes out containing an executable called `testing_17` **and a
  `testing_17.pck`**. The engine loads `<executable-name>.pck`, so renaming only the
  executable breaks the app with *"Couldn't load project data ... Is the .pck file
  missing?"* — **rename both**. The preset's `application/name` is **ignored** in 4.7, and
  `application/config/name` must not be touched, so renaming post-export is the honest way;
  `tools/release.sh` now does it, plus copies `steam_appid.txt` into `Contents/MacOS/`.
- **Zip a `.app` with `ditto -c -k --sequesterRsrc --keepParent`, never plain `zip`** — a
  bundle needs its metadata and executable bit, and `ditto` is what preserves them.
- **An unsigned macOS app is quarantined by Gatekeeper when someone downloads it** — the
  tester sees "cannot be opened because the developer cannot be verified", or "it is
  damaged". That is not a broken build. Right-click -> Open bypasses it, or
  `xattr -dr com.apple.quarantine SteamMMO.app`. Say this on the download page, or friends
  will report the game as broken. (Running the app locally is unaffected: quarantine only
  applies to downloaded copies.)
- **Do not run a packaged build with the project directory as the working directory** — the
  engine then finds `project.godot` in the CWD and behaves as if overridden. Run it from
  `/tmp` or similar when smoke-testing, and note that the exported binary supports
  `--headless --quit`, which is the cheapest real test there is: it boots the packaged
  `.pck`, initialises Steam, prints the build identity, and exits.
- **The Web export warns `No "wasm32" library found for GDExtension: godotsteam`.** Expected
  and harmless: there is no web binary of the Steam extension, so it is simply absent from
  the web build — which is why `SteamManager`'s `Engine.has_singleton("Steam")` guard is the
  thing that keeps the browser build alive.
- **The `[dotnet]` marker in `project.godot` is harmless — this was measured, not assumed.**
  The tree contains **zero C# files**, yet `project.godot` still carries
  `[dotnet] project/assembly_name="testing_17"`, left there by the mono editor that created
  the project. The **standard non-.NET Godot 4.7 editor opens the project with that marker
  present, with no error**: GodotSteam loads, Steam initializes, and the GUT suite runs
  **161/161**. Do not "clean up" the marker hoping to fix something, and do not assume a
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
opens it, initialises Steam and passes **161/161**, exactly like the mono editor. The game
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

**What is verified, and what is not — read this before believing a web build works.**
The export completes cleanly, the files are complete and serve over HTTP, and in a real
browser the build reaches the **start screen**, drawn completely. That is where the good
news ends: **the menu is inert.** The game's own errors go to the *browser's* console, where
nothing local sees them, and what they say is:

    ERROR: Failed to instantiate an autoload, script 'res://autoload/SteamManager.gd'
           does not inherit from 'Node'.      (same for NetworkManager.gd and NetStats.gd)
    SCRIPT ERROR: Parse Error: Identifier "Steam" not declared in the current scope.
    SCRIPT ERROR: Parse Error: Could not find type "SteamMultiplayerPeer".

A browser has no GodotSteam, so there is no `Steam` global and no `SteamMultiplayerPeer`
*t*ype — and these are **parse-time** failures, so the whole script is rejected before a line
of it runs. The runtime guard (`Engine.has_singleton("Steam")`) is therefore useless here: it
sits inside a file that never gets to execute. Those three autoloads never instantiate and
every button that talks to `NetworkManager` does nothing.

Two traps that caused an earlier WRONG conclusion, both now covered by a tool:

- **Headless Chrome is not an instrument for this.** It stops at the loading splash and
  reports nothing, reproducibly, whatever renderer is forced (`--use-angle=metal`,
  `--enable-unsafe-swiftshader`) — that is a limit of software rendering, not a verdict.
- **A screenshot is not an instrument either.** It shows a beautiful, dead menu. Only the
  browser's own console tells the truth.

Use the tool instead, and do not trust a picture:

    tools/web_smoke.sh          # real Chrome in its own profile, prints the game's console,
                                # verdicts FAIL/PASS, non-zero exit on this exact failure
                                # --port N / --wait S / --keep-open

It captures **only the browser window's rectangle**, never the whole screen: a full-screen
grab on someone's working machine catches whatever else is open on it. (`screencapture` needs
Screen Recording permission for the terminal; a blank or desktop-only picture is that
permission, not a build verdict.) Deliberately do **not** use `open -a "Google Chrome"` for
this: on an already-running Chrome it just focuses the existing window and ignores every flag,
which is how an early attempt "tested" the wrong window entirely.

The browser build is therefore **produced but not shippable** until a fix lands; the options
(A: web-only shims, B: take Steam out of the parse path, C: drop the html5 channel) are
weighed in `ITCH.md`. Fixing it still only buys a **single-player** browser demo — a browser
cannot open a UDP socket, so no transport can ever work there.

## macOS packaging: re-sign, always

`tools/release.sh` **must** ad-hoc sign the macOS bundle (`codesign --force --deep --sign -`) after it
renames the binary and rewrites `Info.plist`, and must fail if `codesign --verify --deep --strict`
does not pass. Godot's export template ships signed by Godot's own Developer ID; our rename breaks
that signature, and a broken signature makes macOS reject the app as **damaged** on any quarantined
(i.e. downloaded) copy. 0.0011 shipped this way; 0.0012 fixed it. When checking a bundle, extract with
`ditto -x -k` -- plain `unzip` loses bundle metadata and produces false failures.
