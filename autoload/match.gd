extends Node
## Match -- the 1v1 matchmaking POC.
## ============================================================================
## A "match" is a short timed round fought in a separate arena level, then a return
## to whatever lobby level the session came from. It is HOST-AUTHORITATIVE: the
## server starts it, every peer swaps to the arena, a 30s clock runs on the world
## clock, and the server ends it for everyone.
##
## This is the whole of matchmaking for the POC: one button, one round, no queue.
## It rides the EXISTING session (no re-lobby), so a player is never dropped between
## the lobby and the match.
##
## Written by Pollux; landed by Castor.

## The pure rulebook. Referenced by path (not a global class name) so this file never
## depends on the editor's class cache being warm.
const Rules := preload("res://scripts/arena/match_rules.gd")

## Emitted on every peer when a round begins. `duration` is the round length.
signal match_started(duration: float)
## Emitted on every peer when the round ends and the lobby level comes back.
signal match_ended()

## True from the moment the round starts until it ends. Read by the HUD and main.gd.
var in_match: bool = false
## World-clock time the round began. The rulebook turns this into a countdown; a local
## estimate, so every peer draws roughly the same number.
var _started_at: float = 0.0


## Ask for a match. ANY player may call this; the server is the one that starts it, so a
## client's press travels to the host instead of running locally.
func request_match() -> void:
	if in_match:
		return
	if multiplayer.is_server():
		_begin()
	else:
		rpc_id(1, "_server_request")


## Seconds left in the round, 0 when none is running. Delegates to the rulebook.
func remaining() -> float:
	if not in_match:
		return 0.0
	return Rules.remaining(_started_at, WorldState.world_time)


## No real network (editor / offline play): run the match locally instead of over rpc,
## which an OfflineMultiplayerPeer cannot carry.
func _is_offline() -> bool:
	return multiplayer.multiplayer_peer == null \
			or multiplayer.multiplayer_peer is OfflineMultiplayerPeer


@rpc("any_peer", "call_remote", "reliable")
func _server_request() -> void:
	if multiplayer.is_server():
		_begin()


## Server-only entry, guarded so a stray client call cannot start a match.
func _begin() -> void:
	if not multiplayer.is_server() or in_match:
		return
	if _is_offline():
		_start_match()
	else:
		rpc("_start_match")


@rpc("authority", "call_local", "reliable")
func _start_match() -> void:
	in_match = true
	_started_at = WorldState.world_time
	print("[Match] 1v1 round started (%.0fs)." % Rules.DURATION)
	match_started.emit(Rules.DURATION)
	if multiplayer.is_server():
		WorldState.schedule(_finish, Rules.DURATION)


func _finish() -> void:
	if not in_match:
		return
	if _is_offline():
		_end_match()
	else:
		rpc("_end_match")


@rpc("authority", "call_local", "reliable")
func _end_match() -> void:
	in_match = false
	print("[Match] round over; returning to the lobby.")
	match_ended.emit()