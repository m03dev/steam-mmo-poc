class_name QuestDatabase
extends RefCounted
## QuestDatabase -- the placeholder quest catalogue.
##
## Every peer builds exactly the same catalogue from this one file, so quest
## ids, objective counts and rewards agree across the network without a single
## byte being sent. That is the same trick the spawn offsets use: content is
## code, so only *state* has to travel.

const PELTS: String = "pelts"

static var _cache: Dictionary = {}


static func all() -> Array[QuestDef]:
	if _cache.is_empty():
		_build()
	var out: Array[QuestDef] = []
	for key: String in _cache.keys():
		out.append(_cache[key])
	return out


## Look a quest up by id. Returns null when it does not exist, so callers can
## tell "no such quest" from "quest with empty fields".
static func get_quest(quest_id: String) -> QuestDef:
	if _cache.is_empty():
		_build()
	return _cache.get(quest_id, null)


## The quest the placeholder world's quest giver hands out.
static func starter_quest_id() -> String:
	return PELTS


static func _build() -> void:
	_cache.clear()
	var quest: QuestDef = QuestDef.make(
			PELTS,
			"Pelts for the Road",
			"The trader pays for wolf pelts and does not care how you got them.",
			"Trader Vex",
			"wolf_pelt",
			3,
			150,
			"bread",
			2)
	_cache[quest.id] = quest