extends Node
## WorldState -- the globals every world system shares.
##
## Autoload singleton named "WorldState". It exists so that no system has to search
## the scene tree for the others, and so that nothing invents its own clock: the
## entity registry, the world clock, the world timers and the combat log are one
## object, the same object on every peer. That is what "world" means here.
##
## Server-owned facts (the registry the AI reads, the timers) are only ever written
## on the server. The combat log is written on the server and broadcast, so every
## player reads the same story in the same order -- the log is the one place where
## "who hit whom" is allowed to be nothing but the server's opinion.

signal combat_event(text: String)

## Godot's high-level multiplayer always calls the server peer 1, even offline, so
## one constant serves both cases.
const SERVER_ID: int = 1

const KIND_PLAYER: String = "player"
const KIND_ENEMY: String = "enemy"
## The level node itself, so anything that needs to ask the world a question (where
## do players appear, when does a mob come back) can find it without a node path.
const KIND_LEVEL: String = "level"

## How many combat lines are kept. Older ones fall off; nothing depends on them.
const LOG_LIMIT: int = 80

## Seconds the world has been up. One clock, so timed things agree with each other.
var world_time: float = 0.0

## Newest last, capped at LOG_LIMIT.
var combat_log: Array[String] = []

## kind -> Array[Node]. Nodes register themselves as they come and go.
var _registry: Dictionary = {}
## Pending one-shot timers: {at: float, fn: Callable}.
var _timers: Array[Dictionary] = []


func _process(delta: float) -> void:
	world_time += delta
	_run_due_timers()


## True when this peer is the one whose opinion counts, including the offline case
## (Godot's offline peer still answers is_server()).
func is_server() -> bool:
	return multiplayer.multiplayer_peer == null \
			or multiplayer.multiplayer_peer is OfflineMultiplayerPeer \
			or multiplayer.is_server()


#region Registry ----------------------------------------------------------------

## Announce a node so other systems can find it without walking the tree.
func register_entity(kind: String, node: Node) -> void:
	if not _registry.has(kind):
		_registry[kind] = []
	if not _registry[kind].has(node):
		_registry[kind].append(node)


func unregister_entity(kind: String, node: Node) -> void:
	if _registry.has(kind):
		_registry[kind].erase(node)


## Everything of `kind` that still exists.
##
## Freed nodes are dropped on the way out, which is the entire reason this is worth
## having: a caller never has to defend against holding a corpse. (Ask me how the
## enemy AI learned to care about that.)
func entities_in(kind: String) -> Array[Node]:
	var alive: Array[Node] = []
	# Iterated as Variants on purpose: assigning a freed instance to a typed Node
	# variable is itself an engine error, so the validity test has to happen before
	# anything is typed.
	for value: Variant in _registry.get(kind, []):
		if is_instance_valid(value):
			alive.append(value as Node)
	_registry[kind] = alive
	return alive


func count_of(kind: String) -> int:
	return entities_in(kind).size()

#endregion


#region Timers ------------------------------------------------------------------

## Run `fn` once, `delay` seconds from now, on the world clock. The server's alarm
## clock for respawns and anything else that has to happen later.
func schedule(fn: Callable, delay: float) -> void:
	if not is_server():
		return
	_timers.append({"at": world_time + delay, "fn": fn})


func pending_timers() -> int:
	return _timers.size()


func _run_due_timers() -> void:
	if _timers.is_empty():
		return
	var due: Array[Dictionary] = []
	for entry: Dictionary in _timers:
		if float(entry["at"]) <= world_time:
			due.append(entry)
	if due.is_empty():
		return
	for entry: Dictionary in due:
		_timers.erase(entry)
	for entry: Dictionary in due:
		var fn: Callable = entry["fn"]
		if fn.is_valid():
			fn.call()

#endregion


#region Combat log --------------------------------------------------------------

## Say something the whole world should read. Called on the server; broadcast to
## everyone, so two peers cannot disagree about the order of events.
func log_event(text: String) -> void:
	if not is_server():
		return
	if multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_net_log(text)  # nothing to broadcast to
	else:
		rpc("_net_log", text)


@rpc("authority", "call_local", "reliable")
func _net_log(text: String) -> void:
	combat_log.append(text)
	while combat_log.size() > LOG_LIMIT:
		combat_log.pop_front()
	combat_event.emit(text)


## The most recent lines, oldest first, for a log panel to draw.
func recent(count: int) -> Array[String]:
	var start: int = maxi(combat_log.size() - count, 0)
	return combat_log.slice(start)

#endregion