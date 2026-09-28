extends CanvasLayer
## LobbyUI (Step 3) -- TEMPORARY debug harness.
## ----------------------------------------------------------------------------
## Buttons to host / join / auto-join lobbies so the networking layer can be
## tested before any real game flow exists. Delete this whole scene once the
## game drives NetworkManager directly (Step 5).

var _auto_join_done: bool = false


func _ready() -> void:
	# --- Buttons -> NetworkManager -------------------------------------------
	%HostWorldButton.pressed.connect(func() -> void:
		NetworkManager.create_lobby(NetworkManager.TYPE_WORLD))
	%HostDungeonButton.pressed.connect(func() -> void:
		NetworkManager.create_lobby(NetworkManager.TYPE_DUNGEON))
	%JoinButton.pressed.connect(_on_join_pressed)
	%AutoWorldButton.pressed.connect(func() -> void:
		NetworkManager.auto_join_first_open(NetworkManager.TYPE_WORLD))
	%AutoDungeonButton.pressed.connect(func() -> void:
		NetworkManager.auto_join_first_open(NetworkManager.TYPE_DUNGEON))
	%LeaveButton.pressed.connect(NetworkManager.leave_lobby)

	# --- NetworkManager signals -> on-screen feedback ------------------------
	NetworkManager.lobby_created.connect(_on_lobby_created)
	NetworkManager.lobby_create_failed.connect(_on_lobby_create_failed)
	NetworkManager.lobby_joined.connect(_on_lobby_joined)
	NetworkManager.lobby_join_failed.connect(_on_lobby_join_failed)
	NetworkManager.lobby_left.connect(_on_lobby_left)
	NetworkManager.peer_connected.connect(_on_peer_changed)
	NetworkManager.peer_disconnected.connect(_on_peer_changed)
	SteamManager.steam_initialized.connect(_on_steam_initialized)

	_refresh_identity()
	# SteamManager (an autoload) has already resolved init before this scene ran,
	# so decide the initial status ourselves; the signal won't fire again.
	_on_steam_initialized(SteamManager.is_initialized)


func _process(_delta: float) -> void:
	_refresh_identity()


func _on_steam_initialized(success: bool) -> void:
	if not success:
		_set_status("Steam offline -> multiplayer disabled (see Output).")
		return
	_set_status("Steam ready as '%s'." % SteamManager.persona_name)
	# Shipped behaviour: auto-join the open world shortly after launch.
	if %AutoJoinCheck.button_pressed and not _auto_join_done:
		_auto_join_done = true
		await get_tree().create_timer(0.5).timeout
		NetworkManager.auto_join_first_open(NetworkManager.TYPE_WORLD)


func _refresh_identity() -> void:
	if SteamManager.is_initialized:
		%Identity.text = "Steam: %s  (id %d)" % [SteamManager.persona_name, SteamManager.steam_id]
	else:
		%Identity.text = "Steam: not connected"

	if NetworkManager.current_lobby_id != 0:
		%LobbyInfo.text = "Lobby: %d  type=%s  role=%s" % [
				NetworkManager.current_lobby_id,
				NetworkManager.current_lobby_type,
				"host" if NetworkManager.is_host else "client"]
		%Players.text = "Players: %d / %d  (my peer id %d)" % [
				NetworkManager.get_player_count(),
				NetworkManager.MAX_MEMBERS,
				multiplayer.get_unique_id()]
	else:
		%LobbyInfo.text = "Lobby: none"
		%Players.text = "Players: -"


func _on_join_pressed() -> void:
	var text: String = %LobbyIdInput.text.strip_edges()
	if text.is_empty() or not text.is_valid_int():
		_set_status("Enter a numeric Lobby ID first.")
		return
	NetworkManager.join_lobby(int(text))


func _on_lobby_created(lobby_id: int) -> void:
	_set_status("Created lobby %d -- share this ID with the other player." % lobby_id)


func _on_lobby_create_failed(reason: String) -> void:
	_set_status("Create failed: " + reason)


func _on_lobby_joined(lobby_id: int) -> void:
	_set_status("Joined lobby %d." % lobby_id)


func _on_lobby_join_failed(reason: String) -> void:
	_set_status("Join failed: " + reason)


func _on_lobby_left() -> void:
	_set_status("Left lobby.")


func _on_peer_changed(_peer_id: int) -> void:
	_set_status("Peers changed (now %d connected)." % multiplayer.get_peers().size())


func _set_status(text: String) -> void:
	%Status.text = "Status: " + text