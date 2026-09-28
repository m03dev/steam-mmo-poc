class_name Interactable
extends Node3D
## Interactable -- anything the player can walk up to and press E on.
##
## Deliberately not a physics object: a giver or a pickup needs no collision, and
## keeping them out of the physics world means the player can never get wedged on
## one and there are no collision layers to keep in sync. The interactor decides
## what is near by distance instead (see PlayerInteractor).
##
## Subclasses answer two questions -- what should the prompt say, and what happens
## when it is pressed -- and nothing else. They read the LOCAL player's progress
## only to choose text and a marker; every actual change goes through
## PlayerState, which the server validates.

const GROUP: String = "interactable"

## The group net_player.gd puts the local avatar in. Pulled in by PATH rather than
## by class name: a class_name lookup needs Godot's global class cache to be warm,
## which it is not in a headless run (and the editor drops entries it has not
## rescanned), whereas a preload always resolves. This was a real failure, not a
## precaution.
const NetPlayerScript: GDScript = preload("res://scripts/net_player.gd")

## Verb shown in the prompt: "Accept", "Pick up", "Talk to".
@export var prompt_verb: String = "Use"
## Flavour line above the prompt ("Trader Vex").
@export var display_name: String = ""
## Marker glyph floated over the object. Empty means no marker.
@export var marker_text: String = ""
@export var marker_color: Color = Color(1.0, 0.84, 0.25, 1.0)

var _marker: Label3D = null
var _marker_shown: String = ""


func _ready() -> void:
	add_to_group(GROUP)
	if marker_text != "":
		_build_marker()
	# Polling a couple of times a second is plenty for a marker and costs nothing
	# next to a per-frame comparison, and it keeps the marker correct no matter
	# which peer's action changed the state.
	var timer: Timer = Timer.new()
	timer.wait_time = 0.2
	timer.autostart = true
	timer.timeout.connect(_refresh_marker)
	add_child(timer)
	_refresh_marker()


#region For subclasses to answer -------------------------------------------------

## Whether this is worth prompting at all right now.
func is_available_for(_progress: PlayerProgress) -> bool:
	return true


## Text after the key hint: "Accept: Pelts for the Road".
func prompt_text(_progress: PlayerProgress) -> String:
	return prompt_verb


## What pressing the key does. Default: nothing.
func activate(_state: PlayerState) -> void:
	pass


## Marker glyph and colour for the local viewer. Empty text hides the marker.
func marker_for(_progress: PlayerProgress) -> Array:
	return [marker_text, marker_color]


#endregion


#region Marker ------------------------------------------------------------------

func _build_marker() -> void:
	_marker = Label3D.new()
	_marker.name = "Marker"
	_marker.font_size = 96
	_marker.outline_size = 20
	_marker.pixel_size = 0.005
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# Above the tallest thing that carries a marker (a 2m capsule), so the player's
	# own name tag does not sit on top of the glyph exactly when it matters -- as
	# they are walking up to it to read it.
	_marker.position = Vector3(0.0, 2.6, 0.0)
	add_child(_marker)


func _refresh_marker() -> void:
	if _marker == null:
		return
	var result: Array = marker_for(progress_of_local_player())
	var text: String = String(result[0])
	if text == _marker_shown:
		return
	_marker_shown = text
	_marker.text = text
	_marker.visible = text != ""
	if result.size() > 1:
		_marker.modulate = result[1]


## The progress of the player sitting at THIS machine, or null on a headless host
## with no local avatar. Only ever used to choose text.
func progress_of_local_player() -> PlayerProgress:
	var who: Node = get_tree().get_first_node_in_group(NetPlayerScript.LOCAL_PLAYER_GROUP)
	if who == null:
		return null
	var stats: Node = who.get_node_or_null("Stats")
	if stats == null:
		return null
	return (stats as PlayerState).progress

#endregion