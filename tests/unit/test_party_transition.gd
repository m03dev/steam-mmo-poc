extends GutTest

## Pins PARTY TRAVEL: the promise that stepping into the trigger takes the WHOLE party
## with you.
##
## The itch page says "Step into the trigger and the WHOLE PARTY transitions ...
## everyone together, seamlessly", and until this change that was not true: level.gd
## only ever reacted to the avatar on the peer that stepped in, so the others stayed
## behind in a world lobby the first player had already abandoned.
##
## What is pinned here is the DECISION -- a pure function of three flags -- and the
## guards on the Steam callback, which must never ask Steam about a lobby we are not
## in. What is deliberately NOT claimed here is the journey itself: two live Steam
## peers leaving one lobby and meeting in the next is a live test on two machines, and
## a stub that pretends to leave a lobby would prove less than nothing. That run is
## the one arranged with the Windows peer.

var _saved_is_host: bool = false
var _saved_lobby_id: int = 0
var _saved_direct: bool = false
var _saved_started: bool = false


func before_each() -> void:
	# NetworkManager is an autoload and these flags outlive a test, so every test that
	# touches them puts them back -- a stray lobby id would make an unrelated test
	# think it is in a session.
	_saved_is_host = NetworkManager.is_host
	_saved_lobby_id = NetworkManager.current_lobby_id
	_saved_direct = NetworkManager._direct_session
	_saved_started = NetworkManager._party_transition_started


func after_each() -> void:
	NetworkManager.is_host = _saved_is_host
	NetworkManager.current_lobby_id = _saved_lobby_id
	NetworkManager._direct_session = _saved_direct
	NetworkManager._party_transition_started = _saved_started


#region The decision -------------------------------------------------------------

func test_a_direct_link_cannot_travel_at_all() -> void:
	# One host, one port, no lobby list: there is no second session to travel into.
	assert_eq(NetworkManager.transition_move(true, true, true),
			NetworkManager.TransitionMove.REFUSE_DIRECT)
	assert_eq(NetworkManager.transition_move(true, false, true),
			NetworkManager.TransitionMove.REFUSE_DIRECT)


func test_a_session_with_no_lobby_cannot_travel() -> void:
	# Offline play: nobody to bring along, and no Steam to travel through.
	assert_eq(NetworkManager.transition_move(false, true, false),
			NetworkManager.TransitionMove.REFUSE_OFFLINE)
	assert_eq(NetworkManager.transition_move(false, false, false),
			NetworkManager.TransitionMove.REFUSE_OFFLINE)


func test_the_host_broadcasts_and_a_client_asks() -> void:
	# The asymmetry is the whole mechanism: only the lobby owner may write lobby data,
	# and only a client has its own member row to write.
	assert_eq(NetworkManager.transition_move(false, true, true),
			NetworkManager.TransitionMove.BROADCAST)
	assert_eq(NetworkManager.transition_move(false, false, true),
			NetworkManager.TransitionMove.REQUEST)


#endregion


#region Refusals are visible, and leave the trigger armed ------------------------

func test_travel_without_a_session_is_refused_and_says_why() -> void:
	NetworkManager.current_lobby_id = 0
	NetworkManager._direct_session = false
	var started: bool = NetworkManager.request_party_transition(NetworkManager.TYPE_DUNGEON)
	assert_false(started, "level.gd keeps its trigger armed when travel did not start")
	assert_eq(WorldState.combat_log.back(),
			"Nothing to travel to: this session is not on Steam.",
			"a refusal the player cannot see is indistinguishable from a bug")


func test_travel_over_a_direct_link_is_refused_and_says_why() -> void:
	NetworkManager._direct_session = true
	NetworkManager.current_lobby_id = 0
	var started: bool = NetworkManager.request_party_transition(NetworkManager.TYPE_DUNGEON)
	assert_false(started)
	assert_eq(WorldState.combat_log.back(),
			"Dungeons need a Steam session -- direct-IP play is world-only.")


func test_publishing_with_no_lobby_is_refused_before_it_reaches_steam() -> void:
	# The guard has to come first: setLobbyData on lobby 0 is an engine error, not a
	# polite failure.
	NetworkManager.current_lobby_id = 0
	assert_false(NetworkManager._publish_party_transition(NetworkManager.TYPE_DUNGEON))


#endregion


#region The callback's guards -----------------------------------------------------

func test_a_stale_or_failed_update_never_reaches_steam() -> void:
	# GUT fails a test on any engine error, so getting to the end of this method IS the
	# assertion: none of these may call Steam, because lobby 0 does not exist and the
	# session for a foreign id is not ours.
	NetworkManager.current_lobby_id = 0
	NetworkManager._party_transition_started = false
	NetworkManager._on_steam_lobby_data_update(false, 0, 0)
	NetworkManager._on_steam_lobby_data_update(true, 0, 0)
	NetworkManager._on_steam_lobby_data_update(true, 999999, 0)
	NetworkManager._party_transition_started = true
	NetworkManager._on_steam_lobby_data_update(true, 0, 0)
	pass_test("no Steam call was made for a lobby we are not in")


func test_a_new_session_clears_the_travelling_flag() -> void:
	# The trip ENDS when the old session is torn down, and the rejoin that completes it
	# is a NEW session: leaving the flag set would make the party refuse to travel again
	# for the rest of the process.
	NetworkManager.current_lobby_id = 0
	NetworkManager._party_transition_started = true
	NetworkManager.leave_lobby()
	assert_false(NetworkManager._party_transition_started)


## NOT tested here: that _begin_transition() ignores a second call. Reaching its guard
## means reaching transition_to_lobby_type(), which with Steam actually RUNNING (as it
## is in this suite) issues a real requestLobbyList() and can join a live lobby -- a
## test that does that is testing Steam, and can hang on a lobby someone left open.
## The guard is covered from the other side instead, in the stale-update test above:
## once the flag is set, the announcement is dropped before any Steam call.
func test_the_flag_that_guards_it_is_set_before_the_trip_not_after() -> void:
	var source: String = FileAccess.get_file_as_string("res://autoload/NetworkManager.gd")
	var fn_start: int = source.find("func _begin_transition(")
	assert_gt(fn_start, 0, "_begin_transition must exist")
	var body: String = source.substr(fn_start, 400)
	var set_at: int = body.find("_party_transition_started = true")
	var call_at: int = body.find("transition_to_lobby_type(")
	assert_gt(set_at, 0, "the trip must be flagged")
	assert_gt(call_at, 0, "and it must then actually travel")
	assert_lt(set_at, call_at,
			"the flag is raised BEFORE the trip starts, or the callback that returns "
			+ "mid-flight would start a second one")


#endregion


#region The mechanism stays off the wire -----------------------------------------

func test_party_travel_does_not_change_the_wire_format() -> void:
	# The entire reason this is lobby metadata and not an @rpc: a protocol bump would
	# split anyone running the build already on itch, while strangers are being asked
	# to download it.
	assert_eq(NetworkManager.PROTOCOL_VERSION, 3,
			"party travel must not change the wire format")
	assert_eq(NetworkManager.KEY_TRANSITION, "transition_to")
	assert_eq(NetworkManager.KEY_TRANSITION_REQUEST, "request_transition")

#endregion