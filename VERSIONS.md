# Build versions -- "ver control"

One numbered build per change, so any copy sitting on another machine can be
named back to the change that produced it. The step is a fixed **0.0001**:
0.0001, 0.0002, 0.0003, ...

    tools/release.sh "what changed"

exports the Windows build, packages it, copies it to Google Drive
(`My Drive/ver_control/`) and appends an entry below. The current version lives
in `VERSION`. Newest entries are at the bottom.

**Check the size whenever you download one.** A stale copy is almost always a
different size, and that is the quickest way to catch it.

## 0.0001 -- 2026-09-28 05:59

- Start screen + compact dev HUD; right-click camera peek removed; live ping/peers readout over the Steam relay
- `SteamMMO_0.0001.zip` -- 44140665 bytes -- sha256 `f4acd7278a00b50665ed327d3e5da574ee2582a1b7662ea798b0243e7897e44b`

## 0.0002 -- 2026-09-28 06:52

- Fix the Steam connection-status read (wrong dict key meant it never reported) and document the first-import step
- `SteamMMO_0.0002.zip` -- 44142307 bytes -- sha256 `07b0d9596b27a70e150d7dd37d6995c19c1586beeabc03df5ea0d74a97cb2abf`

## 0.0003 -- 2026-09-28 07:03

- Make build identity visible: the game announces its version and wire protocol at startup, publishes them in the lobby, and checks them on join
- `SteamMMO_0.0003.zip` -- 44144312 bytes -- sha256 `f28a60583590266a2e0f5aa443329c239d0b2875dd258175e236da75a64cbf01`

## 0.0004 -- 2026-09-28 07:06

- Add a switchable Steam transport (lobby helpers vs create_host/create_client) with an explicit virtual port, host-published so joiners obey; add --steam-debug for SDR diagnostics
- `SteamMMO_0.0004.zip` -- 44145720 bytes -- sha256 `7bb65b70009e6b6b54f19683cd1fc8c6ddca80d79432804c4a83bd5f5b8295bd`

## 0.0005 -- 2026-09-28 07:21

- Quest loop: giver offers a job, pickups collect, hand-in pays XP and bread. HUD tracker (level/XP/quest line/key hint). 60 tests, 145 asserts.
- `SteamMMO_0.0005.zip` -- 44163249 bytes -- sha256 `dc96aa298414da70204f6428ccaa2c0e01f21e3b11dd978c2fa0c2c7bce4af1b`

## 0.0006 -- 2026-09-28 07:31

- PLAY is the start button (auto-join the open world, or open one if nobody is playing). Quest giver's marker now changes to a green OK when the quest is handed in instead of vanishing. Quest HUD moved top-right, clear of the dev HUD. Marker lifted above the player name tag. Verified live: gold ! marker, [E] prompt, accept fires on a real key press.
- `SteamMMO_0.0006.zip` -- 44163437 bytes -- sha256 `c70369e0b571ebdaec0d83d5cdae543a915af34fb9a1ac7efa1f787b6a97155b`

## 0.0007 -- 2026-09-28 08:23

- Enemies and combat: server-authoritative mob AI (aggro/chase/leash-evade), Health component, server-validated melee, WorldState globals (registry/clock/timers/combat log), combat log HUD. Split replication so server-owned state syncs from the server, not the owning client. Protocol 2.
- `SteamMMO_0.0007.zip` -- 44180419 bytes -- sha256 `d5565c07ed190753ddb76c880296d2fc9d95307ba2518dfa60898372c2f46207`

## 0.0008 -- 2026-09-28 08:27

- Integrates Pollux's in-game chat (Chat autoload, chat box HUD, dev harness) and its two fixes: canonical transport is now the default, and NetStats stops probing a disconnected peer. Chat box laid out bottom-centre so it does not sit under the combat log. Protocol 3 (new RPC-bearing autoload).
- `SteamMMO_0.0008.zip` -- 44177996 bytes -- sha256 `2fb0f031747679dab162b2383b0c5932b622e597935c44b582b5f811645a0a06`

## 0.0009 -- 2026-09-28 08:48

- Pollux's real-game two-peer chat harness (run here: identical transcripts, both peers spawned), Steam launch invites (+connect_lobby is now read, so Join Game from a cold start goes straight in), and a warning when a friends-only session is hosted because Steam's lobby list cannot see friends-only lobbies.
- `SteamMMO_0.0009.zip` -- 44192532 bytes -- sha256 `5d4eb55c9f84b8ec1b3595b23b77c8760b180c74fff4da21e2597ab870bae826`

## 0.0010 -- 2026-09-28 10:19

- macOS + Web builds: itch.io channels, packaged by the release script
- `SteamMMO_0.0010.zip` -- 44233864 bytes -- sha256 `f37e0fe23e1a9206d5059abf42809aba9e836c7999bb9229b973bc2a69e8c4a0` (Windows)
- `SteamMMO_0.0010_macos.zip` -- 66429457 bytes -- sha256 `435c1e147a49890eb416fcecf806246f32e7fd498556ffe5fe4a85cc3944436a` (macOS)
- `build/web/` --  45M -- Web/HTML5, built from the same tree

## 0.0011 -- 2026-09-28 11:39

- direct-IP transport: play over LAN/IP with no Steam (itch builds); --offline/_ready scene-swap bug fixed
- `SteamMMO_0.0011.zip` -- 44258350 bytes -- sha256 `40d2fdf86e13fd969c57919accaf114d4d306b7a772545b3ee2f9369900f88f9` (Windows)
- `SteamMMO_0.0011_macos.zip` -- 66434066 bytes -- sha256 `3d11a3ae66751436d0a1f9db32f42d84a711afacec7ff9243c127f305c0926c9` (macOS)
- `build/web/` --  45M -- Web/HTML5, built from the same tree

