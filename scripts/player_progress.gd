class_name PlayerProgress
extends RefCounted
## PlayerProgress -- a player's level, XP, items and quest states.
##
## Everything the quest loop has to DECIDE lives in here: what state a quest is
## in, whether an objective is met, what the next level costs, what a hand-in
## pays out. There is no networking in this file at all, which is the point --
## PlayerState wraps it for the wire, and the unit tests drive it directly, so
## the interesting rules are provable without a second peer.

enum QuestState {
	NOT_STARTED,   ## never accepted
	IN_PROGRESS,   ## accepted, objective may or may not be met
	TURNED_IN,     ## done and paid
}

## XP to reach level 2. Linear growth on purpose: the curve is content, not
## plumbing, and a linear one makes the tests readable at a glance.
const BASE_XP_PER_LEVEL: int = 100
const XP_STEP_PER_LEVEL: int = 50

var level: int = 1
var xp: int = 0
## item id -> count
var inventory: Dictionary = {}
## quest id -> QuestState as int (ints survive a dictionary round trip cleanly)
var quests: Dictionary = {}


#region Levelling ---------------------------------------------------------------

## Total XP needed to leave `for_level`.
static func xp_needed_for_level(for_level: int) -> int:
	return BASE_XP_PER_LEVEL + (maxi(for_level, 1) - 1) * XP_STEP_PER_LEVEL


func xp_to_next() -> int:
	return xp_needed_for_level(level)


## Progress towards the next level in 0..1, for the XP bar.
func xp_fraction() -> float:
	var needed: int = xp_to_next()
	return 0.0 if needed <= 0 else clampf(float(xp) / float(needed), 0.0, 1.0)


## Add XP and level up as many times as it affords. Returns how many levels were
## gained, so the caller can play a sound or print a line without recomputing it.
func grant_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	xp += amount
	var gained: int = 0
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		gained += 1
	return gained


#endregion


#region Inventory ---------------------------------------------------------------

func item_count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))


func add_item(item_id: String, amount: int = 1) -> void:
	if item_id == "" or amount == 0:
		return
	var total: int = item_count(item_id) + amount
	if total <= 0:
		inventory.erase(item_id)
	else:
		inventory[item_id] = total


## Remove up to `amount`, returning what was actually removed -- the difference
## matters when a client asks to spend more than it holds.
func remove_item(item_id: String, amount: int = 1) -> int:
	var held: int = item_count(item_id)
	var taken: int = mini(held, maxi(amount, 0))
	if taken > 0:
		add_item(item_id, -taken)
	return taken


#endregion


#region Quests ------------------------------------------------------------------

func state_of(quest_id: String) -> QuestState:
	return int(quests.get(quest_id, QuestState.NOT_STARTED)) as QuestState


func has_accepted(quest_id: String) -> bool:
	return state_of(quest_id) == QuestState.IN_PROGRESS


func has_turned_in(quest_id: String) -> bool:
	return state_of(quest_id) == QuestState.TURNED_IN


## How many of the objective the player is carrying, capped at what the quest
## wants so the tracker can never show "7/3".
func objective_progress(quest: QuestDef) -> int:
	if quest == null:
		return 0
	return mini(item_count(quest.objective_item_id), quest.objective_count)


func objective_met(quest: QuestDef) -> bool:
	return quest != null and item_count(quest.objective_item_id) >= quest.objective_count


## Accept a quest. Only from NOT_STARTED -- re-accepting must never reset
## progress, which is why this refuses instead of overwriting.
func accept(quest: QuestDef) -> bool:
	if quest == null or state_of(quest.id) != QuestState.NOT_STARTED:
		return false
	quests[quest.id] = QuestState.IN_PROGRESS
	return true


## Hand a quest in: requires it to be in progress AND the objective to be carried.
## The objective items are consumed, then XP and the item reward are paid.
func turn_in(quest: QuestDef) -> bool:
	if quest == null:
		return false
	if state_of(quest.id) != QuestState.IN_PROGRESS:
		return false
	if not objective_met(quest):
		return false
	remove_item(quest.objective_item_id, quest.objective_count)
	quests[quest.id] = QuestState.TURNED_IN
	grant_xp(quest.xp_reward)
	if quest.reward_item_count > 0 and quest.reward_item_id != "":
		add_item(quest.reward_item_id, quest.reward_item_count)
	return true


#endregion


#region Wire format -------------------------------------------------------------

## Plain-Dictionary snapshot, which is what actually gets replicated. Kept
## explicit rather than reflecting over the object, so the wire format is
## visible in one place and can be extended deliberately.
func to_dict() -> Dictionary:
	return {
		"level": level,
		"xp": xp,
		"inventory": inventory.duplicate(),
		"quests": quests.duplicate(),
	}


## Rebuild from a snapshot. Values are coerced because anything that has been
## through the network arrives as a generic Variant.
static func from_dict(data: Dictionary) -> PlayerProgress:
	var progress: PlayerProgress = PlayerProgress.new()
	progress.level = maxi(int(data.get("level", 1)), 1)
	progress.xp = maxi(int(data.get("xp", 0)), 0)
	var inv: Variant = data.get("inventory", {})
	if inv is Dictionary:
		for key: Variant in inv:
			progress.inventory[String(key)] = int(inv[key])
	var qs: Variant = data.get("quests", {})
	if qs is Dictionary:
		for key: Variant in qs:
			progress.quests[String(key)] = int(qs[key])
	return progress

#endregion