extends GutTest

## Pins the direct (non-Steam) transport: the path a downloaded build takes when the
## player has no Steam at all.
##
## These are the LOCAL decisions only -- which peer gets configured, what the state
## ends up as, and how a typed address is parsed. No test here waits for a second
## machine or a socket to connect: that is what the live two-peer run is for
## (see the harness command in README.md). A test that dialled a real address would
## be an async guess, which is worse than no test.

## A port nothing else in the suite uses, so a test cannot collide with a running host.
const TEST_PORT: int = 24117

## NetworkManager is an autoload, and `multiplayer` belongs to the whole SceneTree:
## a peer left set here changes what every later test sees (a node decides it is
## multiplayer authority by comparing ids, so a stray peer silently disables mob AI
## in an unrelated file). Every test that touches either puts both back.
var _saved_is_host: bool = false
var _saved_lobby_id: int = 0
var _saved_lobby_type: String = ""
var _saved_direct: bool = false
var _saved_peer: MultiplayerPeer = null


func before_each() -> void:
	_saved_is_host = NetworkManager.is_host
	_saved_lobby_id = NetworkManager.current_lobby_id
	_saved_lobby_type = NetworkManager.current_lobby_type
	_saved_direct = NetworkManager.is_direct_session()
	# Normally null. Saving it means these tests are safe to run even inside a live
	# session, and that they cannot hand one to whatever test runs next.
	_saved_peer = multiplayer.multiplayer_peer


func after_each() -> void:
	# Close whatever a test opened BEFORE restoring the flags, so no listener
	# outlives the test.
	NetworkManager.leave_lobby()
	multiplayer.multiplayer_peer = _saved_peer
	NetworkManager.is_host = _saved_is_host
	NetworkManager.current_lobby_id = _saved_lobby_id
	NetworkManager.current_lobby_type = _saved_lobby_type


#region Hosting ------------------------------------------------------------------

func test_hosting_direct_makes_this_peer_the_server() -> void:
	var err: int = NetworkManager.host_direct(TEST_PORT)
	assert_eq(err, OK, "a free UDP port should open")
	assert_true(NetworkManager.is_host, "the host end is the server end")
	assert_true(NetworkManager.is_direct_session(), "and it knows it is not Steam")
	assert_eq(multiplayer.get_unique_id(), 1,
		"the server is always peer 1, which is what every authority rule assumes")
	assert_eq(NetworkManager.current_lobby_id, 0,
		"a direct session has no Steam lobby, and must not pretend to have one")


func test_hosting_direct_announces_itself_once() -> void:
	watch_signals(NetworkManager)
	NetworkManager.host_direct(TEST_PORT)
	# NOTE: no message argument -- GUT's 4th parameter is `index` (an int), so a
	# string there is compared as an index and blows up inside GUT, not here.
	assert_signal_emitted_with_parameters(NetworkManager, "direct_session_started", [true])


func test_hosting_twice_is_refused_rather_than_silently_replacing_the_session() -> void:
	assert_eq(NetworkManager.host_direct(TEST_PORT), OK)
	assert_eq(NetworkManager.host_direct(TEST_PORT), ERR_ALREADY_IN_USE,
		"a second session on top of a live one would drop the players already here")


#endregion


#region Joining -----------------------------------------------------------------

func test_joining_direct_dials_the_address_it_was_given() -> void:
	# 127.0.0.1 with nothing listening: ENet still accepts the dial and reports the
	# failure asynchronously, so OK here means "started", not "connected".
	var err: int = NetworkManager.join_direct("127.0.0.1", TEST_PORT)
	assert_eq(err, OK, "dialling a well-formed address starts even with no host there")
	assert_false(NetworkManager.is_host, "a joiner is never the server")
	assert_true(NetworkManager.is_direct_session(), "and it knows it is not Steam")
	# Close it here rather than only in after_each: a dial left open would report its
	# failure a few seconds later, i.e. during whatever test runs next.
	NetworkManager.leave_lobby()


func test_joining_with_no_address_is_refused_before_a_socket_exists() -> void:
	# Run with no flags and with the user args stripped, so the guard is what is
	# under test rather than anything the command line handed us.
	assert_ne(NetworkManager.join_direct("", TEST_PORT), OK,
		"an empty address is a mistake, not a dial to localhost")
	assert_null(NetworkManager.peer, "and it must not leave a half-open peer behind")


#endregion


#region Address parsing ----------------------------------------------------------

func test_address_parsing_splits_a_port_when_one_is_given() -> void:
	var parsed: Dictionary = NetworkManager.parse_direct_address("192.168.1.20:9000", 23460)
	assert_eq(parsed["address"], "192.168.1.20")
	assert_eq(parsed["port"], 9000)


func test_address_parsing_keeps_the_default_port_for_a_bare_host() -> void:
	var parsed: Dictionary = NetworkManager.parse_direct_address("  example.com  ", 23460)
	assert_eq(parsed["address"], "example.com", "surrounding space is not part of a host")
	assert_eq(parsed["port"], 23460)


func test_address_parsing_treats_an_empty_field_as_no_address() -> void:
	var parsed: Dictionary = NetworkManager.parse_direct_address("   ", 23460)
	assert_eq(parsed["address"], "", "emptiness is the caller's problem, not a hostname")
	assert_eq(parsed["port"], 23460)


func test_address_parsing_ignores_a_colon_that_is_not_a_port() -> void:
	# A mistyped port must not become address "host" on port 23460 and connect
	# somewhere plausible: keeping the whole string means ENet fails loudly instead.
	var parsed: Dictionary = NetworkManager.parse_direct_address("host:notaport", 23460)
	assert_eq(parsed["address"], "host:notaport")


#endregion


#region The dungeon transition, over a direct link -------------------------------

func test_a_dungeon_transition_is_refused_over_a_direct_session() -> void:
	# The dungeon is a second session found through Steam's lobby list. Over a direct
	# link there is one host and one port, so the honest answer is "not supported" --
	# refusing must not tear down the working session on the way out.
	NetworkManager.host_direct(TEST_PORT)
	var before: MultiplayerPeer = NetworkManager.peer
	NetworkManager.transition_to_lobby_type(NetworkManager.TYPE_DUNGEON)
	assert_eq(NetworkManager.peer, before,
		"the session is still up: a refused transition must not disconnect anyone")
	assert_true(NetworkManager.is_direct_session(), "and it is still a direct session")
	assert_eq(NetworkManager.current_lobby_type, NetworkManager.TYPE_WORLD,
		"the level type did not change, because nothing was joined")


#endregion


#region Leaving ------------------------------------------------------------------

func test_leaving_closes_a_direct_session_completely() -> void:
	NetworkManager.host_direct(TEST_PORT)
	assert_not_null(NetworkManager.peer)
	NetworkManager.leave_lobby()
	assert_null(NetworkManager.peer, "no peer outlives the session")
	assert_false(NetworkManager.is_direct_session(), "and the direct flag is cleared")
	assert_false(NetworkManager.is_host, "as is the host flag")


#endregion