class_name QuestGiver
extends "res://scripts/interactable.gd"
## QuestGiver -- an NPC that hands out one quest and takes it back.
##
## The classic three-glyph convention, derived locally: "!" when the quest is
## available, "?" while it is under way and greyed until the objective is met,
## nothing once it has been handed in. None of that state is sent over the
## network -- each peer works it out from its own player's replicated progress,
## which is why the marker is always right without a single extra packet.

## Which quest in QuestDatabase this NPC is responsible for.
@export var quest_id: String = "pelts"

## What pressing the key does here. Pure and static so the unit tests can drive
## the decision directly instead of spawning a scene and faking input.
enum Action { NONE, ACCEPT, TURN_IN }


static func action_for(progress: PlayerProgress, quest: QuestDef) -> Action:
	if progress == null or quest == null:
		return Action.NONE
	if progress.has_turned_in(quest.id):
		return Action.NONE
	if not progress.has_accepted(quest.id):
		return Action.ACCEPT
	if progress.objective_met(quest):
		return Action.TURN_IN
	return Action.NONE


func quest() -> QuestDef:
	return QuestDatabase.get_quest(quest_id)


func is_available_for(progress: PlayerProgress) -> bool:
	return action_for(progress, quest()) != Action.NONE


func prompt_text(progress: PlayerProgress) -> String:
	var the_quest: QuestDef = quest()
	if the_quest == null:
		return display_name
	match action_for(progress, the_quest):
		Action.ACCEPT:
			return "Accept: %s" % the_quest.title
		Action.TURN_IN:
			return "Hand in: %s" % the_quest.title
		_:
			return "%s has nothing more for you" % display_name


func marker_for(progress: PlayerProgress) -> Array:
	var the_quest: QuestDef = quest()
	if the_quest == null:
		return ["", marker_color]
	match action_for(progress, the_quest):
		Action.ACCEPT:
			return ["!", Color(1.0, 0.84, 0.25, 1.0)]
		Action.TURN_IN:
			return ["?", Color(1.0, 0.84, 0.25, 1.0)]
		_:
			if progress != null and progress.has_accepted(the_quest.id):
				return ["?", Color(0.55, 0.55, 0.55, 1.0)]
			return ["", marker_color]


## Ask the server to accept or hand in. The decision here is only a HINT for the
## prompt; the server runs the same rule against the real state and is the only
## thing that can actually change anything.
func activate(state: PlayerState) -> void:
	if state == null:
		return
	var the_quest: QuestDef = quest()
	match action_for(state.progress, the_quest):
		Action.ACCEPT:
			state.request_accept(the_quest.id)
		Action.TURN_IN:
			state.request_turn_in(the_quest.id)
		_:
			pass