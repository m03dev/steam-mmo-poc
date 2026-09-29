class_name Level
extends Node3D
## Level -- blockout used for both the open world and the dungeon.
##
## The host (Godot server) owns the MultiplayerSpawner and is the only peer that
## spawns players. Each spawned player is named "player_<peer_id>" so every peer
## derives the same authority. Walking into $Trigger starts a lobby transition
## (the network half lives in NetworkManager; the level swap lives in main.gd).

@export var level_type: String = "world"
## Where players appear in this level. Spread out per peer so two boxes never
## spawn inside each other (which makes physics fling them apart).
@export var spawn_point: Vector3 = Vector3(0.0, 1.0, 0.0)
## Where the mobs of this level stand.
##
## An array of positions rather than a authored node per mob, because the server
## spawns and respawns them BY INDEX: the index is the whole spawn payload, so
## every peer rebuilds the same mob in the same place from one integer and no
## extra traffic. Empty means "no enemies here" -- which is what the dungeon says.
@export var enemy_spawns: Array[Vector3] = []
## How long a killed mob stays gone.
@export var enemy_respawn_delay: float = 8.0

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")

var _transitioning: bool = false
## Client-only overview camera shown until the host spawns our own box.
var _fallback_cam: Camera3D = null

@onready var spawner: MultiplayerSpawner = $Spawner
@onready var players: Node3D = $Players
@onready var trigger: Area3D = $Trigger
@onready var enemy_spawner: MultiplayerSpawner = get_node_or_null("EnemySpawner") as MultiplayerSpawner
@onready var enemies: Node3D = get_node_or_null("Enemies") as Node3D


func _ready() -> void:
	spawner.spawn_function = _spawn_player
	trigger.body_entered.connect(_on_trigger_entered)
	# The session can outlive its host: NetworkManager decides that and tells us here,
	# because the node surgery it needs is ours to do (see _on_host_migrated).
	NetworkManager.host_migrated.connect(_on_host_migrated)
	# A level announces itself, so anything that needs to know where players appear
	# can find it by group rather than by guessing at node paths.
	add_to_group(WorldState.KIND_LEVEL)
	# Every peer needs the spawn function fitted, including clients that have not
	# received a mob yet: a MultiplayerSpawner rebuilds incoming spawns with it.
	# NOTE: Godot's default multiplayer_peer is an OfflineMultiplayerPeer, NOT
	# null. Testing `== null` alone would make every peer think it is the server,
	# so "are we actually connected to anyone?" must name that class explicitly.
	var offline: bool = multiplayer.multiplayer_peer == null \
			or multiplayer.multiplayer_peer is OfflineMultiplayerPeer
	print("[Level/%s] ready | offline=%s server=%s my_id=%d" % [
			level_type, str(offline), str(multiplayer.is_server()), multiplayer.get_unique_id()])

	if enemy_spawner != null:
		enemy_spawner.spawn_function = _spawn_enemy_node

	# Offline / editor: no real connection, so just spawn a local player.
	if offline:
		_spawn_local()
		_spawn_all_enemies()
		return

	if multiplayer.is_server():
		# Host: it is the only peer that spawns; clients receive the spawns.
		multiplayer.peer_connected.connect(_spawn)
		multiplayer.peer_disconnected.connect(_despawn)
		_spawn(multiplayer.get_unique_id())
		for id in multiplayer.get_peers():
			_spawn(id)
		_spawn_all_enemies()
	else:
		# Client: the host spawns our box and replicates it. Until that arrives
		# we would be staring at a black screen, so watch from a fixed overview
		# camera; our player's camera takes over the moment it spawns.
		_show_fallback_camera()


func _spawn_player(data: Variant) -> Node:
	print("[Level/%s] spawning player_%s" % [level_type, str(data)])
	var player: Node3D = PLAYER_SCENE.instantiate()
	var id: int = int(data)
	player.name = "player_%d" % id
	player.position = spawn_point + spawn_offset_for(id)
	_label_player(player, id)
	return player


#region Mobs --------------------------------------------------------------------

## Spawn every mob this level declares. Server and offline only -- a client's copy
## of this scene receives them from the host instead, which is also how a peer that
## joins later gets the mobs that are already standing there.
func _spawn_all_enemies() -> void:
	if enemy_spawner == null or enemies == null:
		return
	for index in enemy_spawns.size():
		enemy_spawner.spawn(index)


## Builds a mob from nothing but its spawn index. Runs on every peer (the spawner
## calls it here and on each client as the spawn arrives), so the name and the
## position have to be derivable from the index alone -- no per-peer reasoning.
func _spawn_enemy_node(data: Variant) -> Node:
	var index: int = int(data)
	var enemy: Enemy = ENEMY_SCENE.instantiate()
	enemy.name = "enemy_%d" % index
	enemy.spawn_id = index
	if index >= 0 and index < enemy_spawns.size():
		enemy.position = enemy_spawns[index]
	else:
		enemy.position = spawn_point
	return enemy


## Called by a fallen mob. The level owns the clock here on purpose: the spawn point
## belongs to the content, so the respawn delay does too -- and WorldState provides
## the timer, so no node has to run a countdown of its own.
##
## Nothing is despawned and nothing is re-spawned: the mob is still standing there
## with zero hit points, which every peer can see for itself because health is
## replicated. Restoring it is therefore all a revival takes.
func respawn_enemy(enemy: Node) -> void:
	if enemy == null:
		return
	WorldState.schedule(_revive_enemy_now.bind(enemy), enemy_respawn_delay)


func _revive_enemy_now(enemy: Node) -> void:
	# Bound a node into a timer, so it may have been freed in the meantime.
	if is_instance_valid(enemy) and enemy.has_method("revive"):
		enemy.revive()

#endregion


## Deterministic per-peer offset: every peer derives the same spot from the id
## alone, so spawn positions agree across the network with no extra traffic.
## Static and pure, which also makes the spread unit-testable.
static func spawn_offset_for(peer_id: int) -> Vector3:
	return Vector3(float(peer_id % 4) * 2.0 - 3.0, 0.0, 0.0)


func _spawn(id: int) -> void:
	if id <= 0:
		return
	if players.has_node("player_%d" % id):
		return
	print("[Level/%s] server spawn request for %d" % [level_type, id])
	spawner.spawn(id)


func _despawn(id: int) -> void:
	var node: Node = players.get_node_or_null("player_%d" % id)
	if node != null:
		node.queue_free()


## The host left and we took the session over (or followed whoever now owns it).
##
## Taking over means one thing has to change in the SCENE: who `player_1` is. A Godot
## server is always peer 1, and in this codebase the node NAME is the authority, so the
## departed host's avatar has to go and the local one has to take its name. Freeing it
## immediately (not queue_free) matters: a queued free leaves the name taken, Godot
## renames ours to "@player_1@2" to avoid the clash, and every authority in the scene
## silently points at a node nobody has.
func _on_host_migrated(became_host: bool) -> void:
	if not became_host:
		return
	var mine: Node3D = get_tree().get_first_node_in_group(NetPlayer.LOCAL_PLAYER_GROUP) as Node3D
	var theirs: Node3D = players.get_node_or_null("player_1") as Node3D
	if theirs != null and theirs != mine:
		players.remove_child(theirs)
		theirs.free()
	if mine != null:
		mine.name = "player_1"
		# Recursive on purpose: the synchronizers and components under the avatar all
		# belong to whoever owns the new session now, which is us.
		mine.set_multiplayer_authority(1, true)
		var tag: Label3D = mine.get_node_or_null("NameTag") as Label3D
		if tag != null:
			tag.text = SteamManager.name_tag_for(1)
	# We are the server now, so we are the one that spawns and despawns other players.
	if not multiplayer.peer_connected.is_connected(_spawn):
		multiplayer.peer_connected.connect(_spawn)
	if not multiplayer.peer_disconnected.is_connected(_despawn):
		multiplayer.peer_disconnected.connect(_despawn)
	print("[Level/%s] took the session over: player_1 is the local avatar now." % level_type)


func _spawn_local() -> void:
	var player: Node3D = PLAYER_SCENE.instantiate()
	player.name = "player_1"
	player.position = spawn_point
	_label_player(player, 1)
	players.add_child(player)


## Float a name tag over every player -- pure testing clarity, so it is obvious
## which character is yours and which belongs to the other peer.
##
## The tag names the ACCOUNT, not the peer id: a second line carries the SteamID64
## and the local avatar is marked "(you)". "player_2" tells a screenshot nothing --
## every session numbers its peers the same way -- whereas 76561198632049032 is the
## Windows account and 76561198063757123 is the Mac one, and Steam's own name for
## each sits on top. A direct-IP session has no Steam identity to show, so there the
## tag stays the replication name it always was (SteamManager.name_tag_for decides).
func _label_player(player: Node3D, id: int) -> void:
	var label: Label3D = Label3D.new()
	label.name = "NameTag"
	label.text = SteamManager.name_tag_for(id)
	label.font_size = 48
	label.outline_size = 12
	label.pixel_size = 0.004
	# The second line (the account number) needs room: the default spacing would
	# let a three-line tag overlap itself.
	label.line_spacing = -0.15
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color.from_hsv(float(abs(id) % 12) / 12.0, 0.65, 1.0)
	label.position = Vector3(0.0, 2.55, 0.0)
	player.add_child(label)


## Client-side overview camera, used only until our own box is spawned by the
## host. Without it a just-joined client renders nothing at all.
func _show_fallback_camera() -> void:
	if _fallback_cam != null:
		return
	_fallback_cam = Camera3D.new()
	_fallback_cam.name = "FallbackCamera"
	_fallback_cam.position = Vector3(0.0, 12.0, 16.0)
	_fallback_cam.rotation_degrees = Vector3(-32.0, 0.0, 0.0)
	add_child(_fallback_cam)
	_fallback_cam.current = true


func _on_trigger_entered(body: Node3D) -> void:
	# Only the local owner reacts, and only once, so a body sitting in the
	# volume does not retrigger the transition every physics frame.
	if _transitioning:
		return
	if body is CharacterBody3D and multiplayer.multiplayer_peer != null \
			and body.is_multiplayer_authority():
		var target: String = NetworkManager.TYPE_DUNGEON if level_type == NetworkManager.TYPE_WORLD else NetworkManager.TYPE_WORLD
		# A direct (no-Steam) link cannot reach a dungeon, because a dungeon is a second
		# session found through Steam's lobby list. That refusal lives in NetworkManager
		# with the rest of the transport knowledge, and says so in the log the player is
		# already reading rather than failing silently here.
		_transitioning = true
		print("[Level] '%s' trigger hit -> transitioning to '%s'." % [level_type, target])
		# WHO travels is NetworkManager's decision now. This used to be local to each
		# peer -- you moved when YOUR body touched the volume -- which quietly made a
		# lie of the page's "the whole party travels together": one player walking in
		# left the others standing in a world lobby the host had already abandoned.
		# The host publishes the target in the lobby's data and a client asks the host
		# through its own member data, so everyone moves (Steam lobby metadata, no new
		# RPC, PROTOCOL unchanged).
		if not NetworkManager.request_party_transition(target):
			# Nothing to travel to (no Steam at all). Leave the trigger armed, so a
			# session that becomes a Steam one later can still use it.
			_transitioning = false