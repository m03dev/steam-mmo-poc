extends RefCounted
## MatchRules -- the PURE rulebook for a 1v1 POC round.
## ============================================================================
## No nodes, no signals, no networking, no clock of its own: every function is a
## pure calculation over numbers handed in, so the rule lives in one place and can
## be unit-tested without a running game.
##
## The wiring (who starts a round, how the session swaps to the arena and back)
## lives elsewhere and ASKS these functions what the rules say. This file is the
## frozen interface between the two halves; do not add state to it.
##
## Written by Pollux; landed by Castor as a preload-by-path (no class_name, which is
## the file-linking convention here).

## Length of one round, in seconds.
const DURATION: float = 30.0


## Seconds left in a round that began at `started_at`, read at time `now`.
## Clamped at 0, so a countdown never shows a negative number past the whistle.
static func remaining(started_at: float, now: float) -> float:
	return maxf(0.0, started_at + DURATION - now)


## True once a round that began at `started_at` has run its full length by `now`.
static func is_finished(started_at: float, now: float) -> bool:
	return now - started_at >= DURATION


## How far through the round we are, 0..1, for a countdown ring or progress bar.
static func progress(started_at: float, now: float) -> float:
	if DURATION <= 0.0:
		return 1.0
	return clampf((now - started_at) / DURATION, 0.0, 1.0)