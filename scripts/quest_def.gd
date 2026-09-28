class_name QuestDef
extends Resource
## QuestDef -- one quest, as data.
##
## A quest is only ever three things here: what it is called, what it wants, and
## what it pays. Objectives are deliberately one item count for now ("bring me N
## of X") because that single objective already exercises the whole loop --
## accept, collect, hand in -- and the honest thing to do is prove the loop
## before widening the data model.
##
## This is a Resource so quests can later be authored as .tres files, but the
## catalogue builds them in code today (see QuestDatabase), which keeps them
## diffable and reviewable in the repository.

@export var id: String = ""
@export var title: String = ""
@export var summary: String = ""
## Who is asking. Purely flavour text for the prompt.
@export var giver_name: String = ""
## The item that must be collected, and how many.
@export var objective_item_id: String = ""
@export var objective_count: int = 1
## Payout.
@export var xp_reward: int = 0
@export var reward_item_id: String = ""
@export var reward_item_count: int = 0


static func make(new_id: String, new_title: String, new_summary: String,
		new_giver_name: String, new_objective_item_id: String, new_objective_count: int,
		new_xp_reward: int, new_reward_item_id: String = "", new_reward_item_count: int = 0) -> QuestDef:
	var quest: QuestDef = QuestDef.new()
	quest.id = new_id
	quest.title = new_title
	quest.summary = new_summary
	quest.giver_name = new_giver_name
	quest.objective_item_id = new_objective_item_id
	quest.objective_count = maxi(new_objective_count, 1)
	quest.xp_reward = maxi(new_xp_reward, 0)
	quest.reward_item_id = new_reward_item_id
	quest.reward_item_count = maxi(new_reward_item_count, 0)
	return quest


## "Collect 3 x Wolf Pelt" -- the objective line the tracker shows.
func objective_text() -> String:
	return "Collect %d x %s" % [objective_count, ItemDatabase.display_name(objective_item_id)]


func reward_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%d XP" % xp_reward)
	if reward_item_count > 0 and reward_item_id != "":
		parts.append("%d x %s" % [reward_item_count, ItemDatabase.display_name(reward_item_id)])
	return "Reward: " + ", ".join(parts)