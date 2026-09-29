# Code guide: small modules, readable on the first pass

Written from the actual state of this codebase, not from theory. The numbers below are real and
were taken with `wc -l`.

## The shape we want

A file should have **one reason to change**. A reader should be able to say what it does in one
sentence before scrolling. Concretely, for this project:

| Size | Meaning |
|------|---------|
| under ~200 lines | comfortable |
| 200-300 | fine if it is one job |
| 300-400 | look for a seam |
| over 400 | a seam already exists; find it before adding anything |

Current reality: `autoload/NetworkManager.gd` is **1051 lines** and does at least five jobs -
Steam lobby lifecycle, Godot multiplayer peer wiring, presence/roster, party travel, and
direct-IP transport. Everything else is between 26 and 261 lines, which is healthy. So this is
one file to fix, not a codebase to rewrite.

## The pattern that has earned its place

Where a behaviour depends on state the tests cannot create (Steam, a live peer, a lobby), split
it in two:

1. a **pure decision function** - all inputs, one return value, no side effects;
2. **thin wiring** that reads the state, calls the decision, and acts.

This is already how the trickiest logic in the project is written, and it is why those parts
have tests at all:

    static func transition_move(is_direct, is_host, in_lobby) -> TransitionMove
    static func needs_announce_grace(is_host_session, member_count) -> bool
    static func parse_direct_address(text, fallback_port) -> ...
    static func identity_text(peer_id, steam_id, persona) -> String

Every one of them is pinned by unit tests that need no Steam, no peer and no lobby. Behaviour
that cannot be tested is usually behaviour that has not been separated yet.

## Splitting NetworkManager (staged; each stage is one commit)

Zero behaviour change, zero wire change, no version bump - internal only. Callers keep working,
because `NetworkManager` stays as a thin facade that delegates. The suite must be green after
every stage, and the live behaviours (host, join, direct, party travel) get a smoke run at the
end.

| Stage | Moves out | Target |
|-------|-----------|--------|
| 1 | direct-IP transport (`host_direct`, `join_direct`, `parse_direct_address`, arg parsing) | `scripts/net/direct_transport.gd` |
| 2 | lobby lifecycle (create/join/leave/list, match-list handling, retries) | `scripts/net/lobby_service.gd` |
| 3 | party travel (`transition_move`, publish/request, `lobby_data_update`) | `scripts/net/party_travel.gd` |
| 4 | what is left: transport choice, peer wiring, roster, delegating API | `autoload/NetworkManager.gd`, under ~250 lines |

Rule for each stage: **move, do not rewrite**. If a test needs rewriting to pass, the seam was
wrong.

## Naming and typing

* Every `var`, parameter and return type is typed. No `var x = f()`.
* Names say what the thing *is*, not what it used to be: `_party_transition_started`, not `_flag2`.
* Constants for anything with a meaning: `ANNOUNCE_GRACE`, `KEY_TRANSITION`.
* Signals are past tense (`lobby_left`), because a signal reports something that happened.

## Comments explain WHY

Three lines that could not be recovered from the code, and are therefore worth their space:

* the host holds the doomed lobby open for `ANNOUNCE_GRACE` - because publishing and leaving in
  the same frame is a race the client can lose silently;
* `lobby_data_update` carries no key and no value in GodotSteam 4.22.1 - so the value is read
  back, and `member_id == 0` is what marks lobby data;
* a client must NOT travel on its own when asked to - it would find or create a different lobby
  from the host's and split the party, which is the bug being fixed.

What does not belong: comments that restate the next line, and comments that describe intent the
code does not implement.

## Tests

* One test file per module in `tests/unit/`, named for the module.
* Pure decisions first: they are the cheap, honest coverage.
* Live claims (two peers, a real lobby, a real transition) come from live runs on two machines,
  and are never inferred from a stub. A test that pretends to be Steam proves less than nothing.

## Not negotiable

* Wire stability: adding an `@rpc` bumps `PROTOCOL_VERSION` and splits anyone on the shipped
  build. Prefer a mechanism that needs no protocol change when strangers are being asked to
  download.
* Authority comes from the node name (`player_<peer_id>`); world state belongs to
  `WorldState.SERVER_ID`.
* Clients request; servers decide.
* Vendored art is read-only.
