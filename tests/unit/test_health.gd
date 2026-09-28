extends GutTest
## Rules coverage for Health -- the component everything that can be hit carries.
##
## No scene, no network: this is the arithmetic and the signals that both the mob
## AI and the player combat path are built on, so it is worth pinning down on its
## own. Anything that gets hit correctly is a consequence of these few rules.

const HealthScript: GDScript = preload("res://scripts/health.gd")

var _health


func before_each() -> void:
	_health = HealthScript.new()
	_health.maximum = 60
	_health.current = 60
	add_child_autofree(_health)
	watch_signals(_health)


#region Taking damage -----------------------------------------------------------

func test_damage_takes_hit_points_and_reports_how_many() -> void:
	var taken: int = _health.apply_damage(14)
	assert_eq(taken, 14, "a hit for 14 takes 14")
	assert_eq(_health.current, 46, "and the total follows")


func test_a_killing_blow_only_reports_what_was_left() -> void:
	var taken: int = _health.apply_damage(999)
	assert_eq(taken, 60, "the report is what was actually taken, not what was asked for")
	assert_eq(_health.current, 0, "hit points stop at zero, never below")


func test_a_dead_thing_cannot_be_hit_again() -> void:
	_health.apply_damage(60)
	assert_false(_health.is_alive(), "it is down")
	assert_eq(_health.apply_damage(10), 0, "and further blows are worth nothing")
	assert_eq(_health.current, 0, "with no negative health to make up later")


func test_nonsense_damage_is_ignored() -> void:
	assert_eq(_health.apply_damage(0), 0)
	assert_eq(_health.apply_damage(-50), 0, "a negative hit must not heal")
	assert_eq(_health.current, 60, "untouched")


#endregion


#region Signals -----------------------------------------------------------------

func test_health_changed_fires_only_when_the_number_moves() -> void:
	_health.apply_damage(10)
	assert_signal_emit_count(_health, "changed", 1, "one change, one signal")
	_health.current = 20
	assert_signal_emit_count(_health, "changed", 2, "a direct write counts too")
	_health.current = 20
	assert_signal_emit_count(_health, "changed", 2, "writing the same value is not a change")


func test_death_is_announced_once_with_the_killer() -> void:
	_health.apply_damage(50, 7)
	assert_signal_emit_count(_health, "died", 0, "hurt is not dead")
	_health.apply_damage(50, 7)
	assert_signal_emit_count(_health, "died", 1, "the killing blow announces itself")
	assert_signal_emitted_with_parameters(_health, "died", [7])
	_health.apply_damage(50, 9)
	assert_signal_emit_count(_health, "died", 1, "a corpse cannot die twice")


func test_damage_is_announced_with_its_amount() -> void:
	_health.apply_damage(25, 3)
	assert_signal_emitted_with_parameters(_health, "damaged", [25, 3])


#endregion


#region Getting up again --------------------------------------------------------

func test_restore_refills() -> void:
	_health.apply_damage(45)
	_health.restore()
	assert_eq(_health.current, 60)
	assert_true(_health.is_alive())


func test_set_maximum_refills_by_default_and_can_keep_the_current_value() -> void:
	_health.set_maximum(100)
	assert_eq(_health.maximum, 100)
	assert_eq(_health.current, 100, "a bigger bar arrives full")

	_health.apply_damage(30)
	_health.set_maximum(50, false)
	assert_eq(_health.maximum, 50)
	assert_eq(_health.current, 50, "keeping the value still clamps it to the new ceiling")


func test_fraction_reports_progress() -> void:
	assert_almost_eq(_health.fraction(), 1.0, 0.001, "full is 1.0")
	_health.apply_damage(30)
	assert_almost_eq(_health.fraction(), 0.5, 0.001, "half is half")
	_health.apply_damage(30)
	assert_almost_eq(_health.fraction(), 0.0, 0.001, "and empty is 0.0")

#endregion