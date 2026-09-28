extends GutTest
## Tests for the quest loop's rules: levelling, inventory, quest state and the
## quest giver's accept-or-hand-in decision.
##
## Everything under test here is deliberately free of networking, which is why
## the whole loop can be proven without a second peer -- the network layer only
## has to deliver the resulting snapshot.

## Preloaded rather than referenced through class_name, so this suite does not
## depend on the global class cache being warm. Locals are therefore untyped on
## purpose: the script object is the only handle we hold.
const ProgressScript: GDScript = preload("res://scripts/player_progress.gd")
const QuestDatabaseScript: GDScript = preload("res://scripts/quest_database.gd")
const QuestGiverScript: GDScript = preload("res://scripts/quest_giver.gd")
const QuestDefScript: GDScript = preload("res://scripts/quest_def.gd")
const ItemDatabaseScript: GDScript = preload("res://scripts/item_database.gd")


func _starter_quest():
	return QuestDatabaseScript.get_quest(QuestDatabaseScript.starter_quest_id())


#region Catalogue ---------------------------------------------------------------

func test_the_starter_quest_exists_and_is_well_formed() -> void:
	var quest = _starter_quest()
	assert_not_null(quest, "the placeholder catalogue must define a starter quest")
	assert_gt(quest.objective_count, 0, "a quest with no objective could never complete")
	assert_true(ItemDatabaseScript.exists(quest.objective_item_id),
			"the objective item must exist in the item catalogue")


func test_quest_ids_are_stable() -> void:
	assert_eq(QuestDatabaseScript.starter_quest_id(), "pelts",
			"the id is content other peers derive locally, so it must not drift")


#endregion


#region Levelling ---------------------------------------------------------------

func test_level_one_needs_the_base_xp() -> void:
	var progress = ProgressScript.new()
	assert_eq(progress.xp_to_next(), 100)
	assert_eq(progress.level, 1)


func test_xp_needed_grows_with_each_level() -> void:
	assert_lt(ProgressScript.xp_needed_for_level(1), ProgressScript.xp_needed_for_level(2))
	assert_lt(ProgressScript.xp_needed_for_level(2), ProgressScript.xp_needed_for_level(3))


func test_granting_enough_xp_levels_up_and_carries_the_remainder() -> void:
	var progress = ProgressScript.new()
	var gained: int = progress.grant_xp(150)
	assert_eq(gained, 1, "150 XP is exactly one level at level 1")
	assert_eq(progress.level, 2)
	assert_eq(progress.xp, 50, "the surplus must carry, not vanish")


func test_one_large_grant_can_cross_several_levels() -> void:
	var progress = ProgressScript.new()
	var gained: int = progress.grant_xp(100 + 150 + 200)
	assert_eq(gained, 3)
	assert_eq(progress.level, 4)
	assert_eq(progress.xp, 0)


func test_zero_or_negative_xp_does_nothing() -> void:
	var progress = ProgressScript.new()
	progress.grant_xp(250)
	var level: int = progress.level
	var xp: int = progress.xp
	assert_eq(progress.grant_xp(0), 0)
	assert_eq(progress.grant_xp(-40), 0)
	assert_eq(progress.level, level)
	assert_eq(progress.xp, xp)


func test_xp_fraction_stays_within_the_bar() -> void:
	var progress = ProgressScript.new()
	assert_eq(progress.xp_fraction(), 0.0)
	progress.grant_xp(50)
	assert_almost_eq(progress.xp_fraction(), 0.5, 0.001)


#endregion


#region Inventory ---------------------------------------------------------------

func test_adding_and_removing_items() -> void:
	var progress = ProgressScript.new()
	progress.add_item("wolf_pelt", 2)
	progress.add_item("wolf_pelt")
	assert_eq(progress.item_count("wolf_pelt"), 3)


func test_removing_more_than_held_takes_only_what_is_there() -> void:
	var progress = ProgressScript.new()
	progress.add_item("wolf_pelt", 2)
	assert_eq(progress.remove_item("wolf_pelt", 5), 2, "returns what it actually took")
	assert_eq(progress.item_count("wolf_pelt"), 0)


func test_an_item_count_never_goes_negative_or_stays_as_zero() -> void:
	var progress = ProgressScript.new()
	progress.add_item("wolf_pelt", 1)
	progress.add_item("wolf_pelt", -1)
	assert_eq(progress.item_count("wolf_pelt"), 0)
	assert_false(progress.inventory.has("wolf_pelt"), "an emptied stack is erased, not left at 0")


#endregion


#region Quest state -------------------------------------------------------------

func test_a_quest_starts_unstarted() -> void:
	var progress = ProgressScript.new()
	assert_eq(progress.state_of("pelts"), ProgressScript.QuestState.NOT_STARTED)
	assert_false(progress.has_accepted("pelts"))


func test_accepting_moves_to_in_progress() -> void:
	var progress = ProgressScript.new()
	assert_true(progress.accept(_starter_quest()))
	assert_true(progress.has_accepted("pelts"))


func test_accepting_twice_is_refused_so_progress_is_never_reset() -> void:
	var progress = ProgressScript.new()
	progress.accept(_starter_quest())
	progress.add_item("wolf_pelt", 2)
	assert_false(progress.accept(_starter_quest()), "re-accepting must not be possible")
	assert_eq(progress.item_count("wolf_pelt"), 2, "and must not have disturbed anything")


func test_handing_in_without_the_objective_is_refused() -> void:
	var progress = ProgressScript.new()
	progress.accept(_starter_quest())
	progress.add_item("wolf_pelt", 2)  # one short
	assert_false(progress.turn_in(_starter_quest()))
	assert_true(progress.has_accepted("pelts"), "still in progress after a refused hand-in")


func test_handing_in_without_accepting_is_refused() -> void:
	var progress = ProgressScript.new()
	progress.add_item("wolf_pelt", 3)
	assert_false(progress.turn_in(_starter_quest()), "you cannot hand in what you never took")


func test_a_full_hand_in_consumes_the_items_and_pays_out() -> void:
	var quest = _starter_quest()
	var progress = ProgressScript.new()
	progress.accept(quest)
	progress.add_item(quest.objective_item_id, quest.objective_count + 1)

	assert_true(progress.turn_in(quest))
	assert_eq(progress.item_count(quest.objective_item_id), 1,
			"exactly the objective is consumed; the spare is kept")
	assert_eq(progress.state_of(quest.id), ProgressScript.QuestState.TURNED_IN)
	assert_eq(progress.level, 2, "the starter reward is worth a level")
	assert_eq(progress.xp, quest.xp_reward - ProgressScript.xp_needed_for_level(1),
			"the XP reward lands, and what is left over carries into the new level")
	assert_eq(progress.item_count(quest.reward_item_id), quest.reward_item_count)


func test_a_hand_in_that_levels_you_up_does_both() -> void:
	var quest = _starter_quest()
	var progress = ProgressScript.new()
	progress.accept(quest)
	progress.add_item(quest.objective_item_id, quest.objective_count)
	progress.turn_in(quest)
	assert_gt(progress.level, 1, "the starter reward is worth at least one level")


func test_a_quest_cannot_be_handed_in_twice() -> void:
	var quest = _starter_quest()
	var progress = ProgressScript.new()
	progress.accept(quest)
	progress.add_item(quest.objective_item_id, quest.objective_count)
	progress.turn_in(quest)
	var xp_after: int = progress.xp
	assert_false(progress.turn_in(quest), "no double rewards")
	assert_eq(progress.xp, xp_after)


func test_objective_progress_is_capped_at_what_the_quest_wants() -> void:
	var quest = _starter_quest()
	var progress = ProgressScript.new()
	progress.add_item(quest.objective_item_id, quest.objective_count + 7)
	assert_eq(progress.objective_progress(quest), quest.objective_count,
			"the tracker must never read 10/3")


#endregion


#region The giver's decision ----------------------------------------------------

func test_giver_offers_an_untaken_quest() -> void:
	var progress = ProgressScript.new()
	assert_eq(QuestGiverScript.action_for(progress, _starter_quest()),
			QuestGiverScript.Action.ACCEPT)


func test_giver_has_nothing_to_offer_while_the_objective_is_incomplete() -> void:
	var progress = ProgressScript.new()
	progress.accept(_starter_quest())
	progress.add_item("wolf_pelt", 1)
	assert_eq(QuestGiverScript.action_for(progress, _starter_quest()),
			QuestGiverScript.Action.NONE)


func test_giver_takes_the_quest_back_once_the_objective_is_met() -> void:
	var quest = _starter_quest()
	var progress = ProgressScript.new()
	progress.accept(quest)
	progress.add_item(quest.objective_item_id, quest.objective_count)
	assert_eq(QuestGiverScript.action_for(progress, quest), QuestGiverScript.Action.TURN_IN)


func test_giver_stops_offering_once_the_quest_is_done() -> void:
	var quest = _starter_quest()
	var progress = ProgressScript.new()
	progress.accept(quest)
	progress.add_item(quest.objective_item_id, quest.objective_count)
	progress.turn_in(quest)
	assert_eq(QuestGiverScript.action_for(progress, quest), QuestGiverScript.Action.NONE)


func test_giver_handles_a_missing_quest_without_crashing() -> void:
	var progress = ProgressScript.new()
	assert_eq(QuestGiverScript.action_for(progress, null), QuestGiverScript.Action.NONE)


#endregion


#region Wire format -------------------------------------------------------------

func test_a_snapshot_survives_the_round_trip() -> void:
	var quest = _starter_quest()
	var progress = ProgressScript.new()
	progress.accept(quest)
	progress.add_item("wolf_pelt", 2)
	progress.add_item("bread", 1)
	progress.grant_xp(260)

	var rebuilt = ProgressScript.from_dict(progress.to_dict())
	assert_eq(rebuilt.level, progress.level)
	assert_eq(rebuilt.xp, progress.xp)
	assert_eq(rebuilt.item_count("wolf_pelt"), 2)
	assert_eq(rebuilt.item_count("bread"), 1)
	assert_eq(rebuilt.state_of("pelts"), ProgressScript.QuestState.IN_PROGRESS)


func test_rebuilding_from_an_empty_snapshot_yields_a_fresh_player() -> void:
	var rebuilt = ProgressScript.from_dict({})
	assert_eq(rebuilt.level, 1)
	assert_eq(rebuilt.xp, 0)
	assert_eq(rebuilt.item_count("wolf_pelt"), 0)


func test_a_snapshot_does_not_alias_the_live_inventory() -> void:
	var progress = ProgressScript.new()
	progress.add_item("wolf_pelt", 1)
	var snapshot: Dictionary = progress.to_dict()
	progress.add_item("wolf_pelt", 1)
	assert_eq(int(snapshot["inventory"]["wolf_pelt"]), 1,
			"a published snapshot must be a copy, not a live view")

#endregion