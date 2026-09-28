class_name PlayerInteractor
extends Node
## PlayerInteractor -- the local player's "press E" logic.
##
## Lives on every player node but only ever runs for the one this machine owns.
## It does two jobs: work out which nearby interactable should be prompted (by
## distance, not physics), and forward the key press to it.
##
## The prompt is UI state and stays local -- a remote player's prompt is nobody
## else's business, so nothing here is replicated.

## How close the player has to be, in metres, to interact with something.
@export var interact_range: float = 3.0
## Seconds between proximity scans. A prompt does not need per-frame accuracy.
@export var scan_interval: float = 0.15

signal prompt_changed(text: String)

## The interactable the prompt is currently about, or null.
var current: Interactable = null

var _character: Node3D = null
var _state: PlayerState = null
var _timer: float = 0.0
var _prompt: String = ""


func _ready() -> void:
	_character = get_parent() as Node3D
	if _character != null:
		_state = _character.get_node_or_null("Stats") as PlayerState
	# Only the owning peer looks for prompts or reads the keyboard.
	var offline: bool = multiplayer.multiplayer_peer == null \
			or multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	var drive: bool = offline or _character.is_multiplayer_authority()
	set_process(drive)
	set_process_unhandled_input(drive)


func _process(delta: float) -> void:
	_timer += delta
	if _timer < scan_interval:
		return
	_timer = 0.0
	_rescan()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		interact()
		get_viewport().set_input_as_handled()


## Do whatever the prompt is currently offering.
##
## Public on purpose: the key press is not the only way in, so tests (and later a
## touch or UI button) can drive the loop without synthesising input events.
func interact() -> void:
	if current != null and _state != null:
		current.activate(_state)


## Re-scan right now instead of waiting for the next tick. Worth calling after a
## teleport or a level swap -- and it is what lets a test drive the loop without
## guessing at frame timing.
func refresh() -> void:
	_timer = 0.0
	_rescan()


## Nearest available interactable within range becomes the prompt. Ties go to the
## closer one, so walking between two objects never picks the one behind you.
func _rescan() -> void:
	if _character == null:
		return
	var progress: PlayerProgress = _progress()
	var here: Vector3 = _character.global_position
	var best: Interactable = null
	var best_distance: float = interact_range
	for node: Node in get_tree().get_nodes_in_group(Interactable.GROUP):
		var target: Interactable = node as Interactable
		if target == null or not target.is_available_for(progress):
			continue
		var distance: float = here.distance_to(target.global_position)
		if distance <= best_distance:
			best = target
			best_distance = distance
	current = best
	_set_prompt("" if best == null else best.prompt_text(progress))


func _progress() -> PlayerProgress:
	return null if _state == null else _state.progress


func _set_prompt(text: String) -> void:
	if text == _prompt:
		return
	_prompt = text
	prompt_changed.emit(text)


## What the HUD should show above the key hint, e.g. "Accept: Pelts for the Road".
func prompt() -> String:
	return _prompt