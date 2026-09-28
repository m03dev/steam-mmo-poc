extends GutTest
## Tests for the lobby layer's derivable logic.
## ============================================================================
## Deliberately Steam-free: every case here is computable from plain values, so
## the suite runs headless with no client, no account and no network.

func test_lobby_types_are_distinct() -> void:
	assert_eq(NetworkManager.TYPE_WORLD, "world")
	assert_eq(NetworkManager.TYPE_DUNGEON, "dungeon")
	assert_ne(NetworkManager.TYPE_WORLD, NetworkManager.TYPE_DUNGEON)


func test_lobby_capacity_is_sane() -> void:
	assert_gt(NetworkManager.MAX_MEMBERS, 1, "a lobby must fit at least two peers")


## GodotSteam hands the lobby match list back as Array[Dictionary], but the
## helper also accepts a bare int so a format change cannot crash us.
func test_lobby_id_of_accepts_a_bare_int() -> void:
	assert_eq(NetworkManager._lobby_id_of(12345), 12345)


func test_lobby_id_of_reads_every_dictionary_key_it_supports() -> void:
	assert_eq(NetworkManager._lobby_id_of({"lobby_id": 7}), 7)
	assert_eq(NetworkManager._lobby_id_of({"steam_id": 8}), 8)
	assert_eq(NetworkManager._lobby_id_of({"id": 9}), 9)


func test_lobby_id_of_ignores_junk_instead_of_erroring() -> void:
	assert_eq(NetworkManager._lobby_id_of("nonsense"), 0)
	assert_eq(NetworkManager._lobby_id_of({}), 0)
	assert_eq(NetworkManager._lobby_id_of(null), 0)


func test_player_queries_are_empty_without_a_lobby() -> void:
	if NetworkManager.current_lobby_id != 0:
		pending("a live lobby is active in this session")
		return
	assert_eq(NetworkManager.get_player_count(), 0)
	assert_eq(NetworkManager.get_lobby_ids().size(), 0)


## leave_lobby() must be safe to call when there is nothing to leave: the level
## transition calls it unconditionally before joining the next lobby.
func test_leave_lobby_is_safe_without_a_session() -> void:
	NetworkManager.leave_lobby()
	assert_eq(NetworkManager.current_lobby_id, 0)
	assert_eq(NetworkManager.current_lobby_type, "")
	assert_false(NetworkManager.is_host)
	assert_null(NetworkManager.peer)