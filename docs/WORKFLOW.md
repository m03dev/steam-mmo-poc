# How Castor (Mac) and Pollux (Windows) work together

Two agents on two machines, one shared Drive folder, one shared repo. This is the protocol,
written after a specific failure so that the failure cannot repeat silently.

## What went wrong, in one paragraph

We agreed a plan, then both started moving. Pollux gated and pushed 0.0013 while Castor found
a race and restarted the host on a *fixed tree* that was a commit ahead of the build on itch.
Nothing was wrong with either half - the version string was. It said `0.0013` for two different
sets of bytes running in the same lobby id, so each side was reasoning from stale facts. That is
the whole disease: **a claim about state that no command can check.**

## The source of truth is git

`https://github.com/m03dev/steam-mmo-poc` - public, cloneable with no credentials, so neither
agent needs an account or a token to read it.

* Code, tests, tools and docs live in git. Nothing else is authoritative.
* The shared Drive is for **messages, artifacts and lobby ids** - never for code. A file that
  exists only in Drive is a file with no history.
* The repo tip and the *shipped artifact* may legitimately differ. When they do, `VERSIONS.md`
  says so, and `docs/RELEASES.md`-style ledger entries name the bytes, not the intent.

### Getting git on the Windows box

    winget install --id Git.Git -e            # needs admin once

No admin? MinGit is a portable zip that needs none: download `MinGit-<ver>-64-bit.zip` from the
git-for-windows releases page, extract it anywhere, and put its `cmd` folder on PATH. Git for
Windows also brings **Git Bash**, which runs our `tools/*.sh` scripts unchanged.

    git clone https://github.com/m03dev/steam-mmo-poc.git
    cd steam-mmo-poc && bash tools/sync_check.sh

## The loop: one topic, one question, one answer

1. Whoever holds the open question says so, and says what they will do while waiting.
2. The other side answers *that* before starting anything new.
3. Nobody starts a second topic while one is open. Parallel work is fine; parallel *questions*
   are how two people talk past each other.

## The state line: the rule that would have caught it

Before any shared test or release, both sides paste the output of:

    bash tools/sync_check.sh

    STATE agent=castor sha=a5bb741 ver=0.0013 protocol=3 dirty=1

A shared test is valid only when both lines agree on **sha + version + protocol**, or when a
difference is stated out loud on purpose ("I am running the served artifact, you are running the
tree; the difference is host-only code"). Anything else is two people testing two things and
calling it one thing.

## Ownership

One writer per tree, no exceptions:

| Owner  | Files |
|--------|-------|
| Castor | `autoload/`, `scripts/`, `scenes/Player.tscn`, `scenes/Main.tscn`, `ui/`, `tests/`, `tools/`, releases, docs |
| Pollux | `scenes/World.tscn`, `scenes/Dungeon.tscn`, `Map/` |
| Neither| the vendored art: `PlayerCharacter/`, `Map/`, `Arts/` - read-only |

Branch per topic, `castor/<topic>` and `pollux/<topic>`, merged to `main` only when the suite is
green. `main` must always be releasable.

## Freeze, and the one-cut rule

* **While a shared test is pending, nobody edits, commits or cuts.** A frozen artifact under test
  is worth more than an improved one.
* **A change that alters shipped bytes needs its own version.** One fix, one version, one cut,
  one push, one verification. Never re-cut a version that is already live - same number,
  different bytes, no way to tell them apart afterwards.
* A claim on the itch page ships only when it has been **observed on two machines, on the served
  bytes**. "Should work" is not a claim; it is a hope with a version number.

## The channel

`agent-comms/` on the shared Drive: `messages/from-<agent>.md` is a channel keyed on the
MACHINE, `LOBBY.md` holds the live host, `HEARTBEAT-<agent>.md` is written but never watched
(two watchers watching heartbeats would ping-pong forever). `tools/drive_watch.sh` polls the
folder, keeps a digest, and notifies - it makes *waiting* visible. It cannot wake an agent:
agents run only when a human speaks, and nothing should pretend otherwise.
