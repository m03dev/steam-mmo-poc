class_name PlayerState
extends Node
## PlayerState -- the network half of a player's progress.
##
## This node is deliberately NOT owned by the player it describes. The character
## node is owned by the peer driving it (that is what makes movement work), but
## XP, items and quest state must not be: a client that owns its stats could hand
## itself a million XP. So this node's authority is the SERVER (peer 1) on every
## peer, it is only ever written on the server, and the resulting snapshot is
## replicated down by the Player scene's MultiplayerSynchronizer.
##
## Clients therefore do exactly two things: ask the server (validated RPCs) and
## display what comes back (net_state).
##
## All the actual rules live in PlayerProgress; this file is plumbing and
## authorisation, and nothing else.

## Godot's high-level multiplayer always calls the server peer 1, even when the
## game is running offline -- so one constant serves both cases.
const SERVER_ID: int = 1

## The replicated snapshot. Replicates server -> everyone; see Player.tscn's
## SceneReplicationConfig, which carries this property with spawn=true so a peer
## joining later still receives the state it missed.
@export var net_state: Dictionary = {}

signal changed


var progress: PlayerProgress = PlayerProgress.new()

## Cheap change detector for incoming replication: comparing the stringified
## snapshot is value-based, unlike comparing two Dictionary references.
var _seen: String = ""


func _enter_tree() -> void:
	# The whole point of this node: the server owns it, nobody else.
	set_multiplayer_authority(SERVER_ID)


func _ready() -> void:
	if is_server():
		_publish()
	else:
		_apply_net_state()


func is_server() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


func _process(_delta: float) -> void:
	if is_server():
		return
	var incoming: String = str(net_state)
	if incoming != _seen:
		_apply_net_state()


## The peer id of the player this state belongs to, derived from the parent
## character's name ("player_<peer_id>") -- the same rule the adapter and the
## level use, so there is one source of truth for who is who.
func peer_id() -> int:
	var parent: Node = get_parent()
	if parent == null:
		return 0
	return int(String(parent.name).trim_prefix("player_"))


#region Incoming state (every peer) ---------------------------------------------

func _apply_net_state() -> void:
	_seen = str(net_state)
	progress = PlayerProgress.from_dict(net_state)
	changed.emit()


#endregion


#region Outgoing state (server only) --------------------------------------------

func _publish() -> void:
	net_state = progress.to_dict()
	_seen = str(net_state)
	changed.emit()


## Only the peer that owns a player may act for it. `sender` is 0 for a call made
## locally by the server itself, which is legitimate -- it is the server acting on
## its own player.
func _may_act_for(sender: int) -> bool:
	if sender == 0:
		return true
	if sender == peer_id():
		return true
	push_warning("[PlayerState] peer %d tried to act for player_%d" % [sender, peer_id()])
	return false

#endregion


#region Server-side awards -------------------------------------------------------

## Hand out XP for something that is not a quest hand-in -- a kill, a discovery,
## anything. Server-only: XP is worth handing yourself, so nobody else may.
## Goes through the same _publish() path as everything else, which is why a kill
## lights up every peer's XP bar with no extra plumbing.
func award_xp(amount: int, reason: String = "") -> void:
	if not is_server() or amount <= 0:
		return
	var level_before: int = progress.level
	progress.grant_xp(amount)
	print("[PlayerState/%d] +%d XP%s | level %d%s" % [
			peer_id(), amount,
			" (%s)" % reason if reason != "" else "",
			progress.level,
			" (LEVEL UP)" if progress.level > level_before else ""])
	_publish()

#endregion


#region Requests (called by any peer, honoured by the server) --------------------

## Client entry points. On the server these run inline; on a client they are
## addressed at peer 1. The RPCs themselves are "call_remote", so a client never
## runs a handler locally and the server never receives its own echo.
func request_accept(quest_id: String) -> void:
	if is_server():
		_handle_accept(multiplayer.get_unique_id(), quest_id)
	else:
		_net_accept.rpc_id(SERVER_ID, quest_id)


func request_turn_in(quest_id: String) -> void:
	if is_server():
		_handle_turn_in(multiplayer.get_unique_id(), quest_id)
	else:
		_net_turn_in.rpc_id(SERVER_ID, quest_id)


func request_pickup(item_id: String, amount: int, node_path: String) -> void:
	if is_server():
		_handle_pickup(multiplayer.get_unique_id(), item_id, amount, node_path)
	else:
		_net_pickup.rpc_id(SERVER_ID, item_id, amount, node_path)


@rpc("any_peer", "call_remote", "reliable")
func _net_accept(quest_id: String) -> void:
	if is_server():
		_handle_accept(multiplayer.get_remote_sender_id(), quest_id)


@rpc("any_peer", "call_remote", "reliable")
func _net_turn_in(quest_id: String) -> void:
	if is_server():
		_handle_turn_in(multiplayer.get_remote_sender_id(), quest_id)


@rpc("any_peer", "call_remote", "reliable")
func _net_pickup(item_id: String, amount: int, node_path: String) -> void:
	if is_server():
		_handle_pickup(multiplayer.get_remote_sender_id(), item_id, amount, node_path)

#endregion


#region Server-side handlers ----------------------------------------------------

func _handle_accept(sender: int, quest_id: String) -> void:
	if not _may_act_for(sender):
		return
	var quest: QuestDef = QuestDatabase.get_quest(quest_id)
	if quest == null:
		return
	if progress.accept(quest):
		print("[PlayerState/%d] accepted '%s'" % [peer_id(), quest_id])
		_publish()


func _handle_turn_in(sender: int, quest_id: String) -> void:
	if not _may_act_for(sender):
		return
	var quest: QuestDef = QuestDatabase.get_quest(quest_id)
	if quest == null:
		return
	# Remember the level before the hand-in so the log can say whether it was the
	# turn-in that levelled the player up.
	var level_before: int = progress.level
	if progress.turn_in(quest):
		print("[PlayerState/%d] turned in '%s' | +%d XP | level %d%s" % [
				peer_id(), quest_id, quest.xp_reward, progress.level,
				" (LEVEL UP)" if progress.level > level_before else ""])
		_publish()


func _handle_pickup(sender: int, item_id: String, amount: int, node_path: String) -> void:
	if not _may_act_for(sender):
		return
	if not ItemDatabase.exists(item_id):
		push_warning("[PlayerState] pickup of unknown item '%s' ignored" % item_id)
		return
	progress.add_item(item_id, maxi(amount, 1))
	_publish()
	# Resolve the pickup by the path the caller sent and let IT decide how to
	# disappear -- the server is the only peer allowed to trigger that.
	var pickup: Node = get_node_or_null(node_path)
	if pickup != null and pickup.has_method("consume_everywhere"):
		pickup.consume_everywhere()

#endregion