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

