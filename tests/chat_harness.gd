extends Node
## Dev harness (NOT shipped) - proves the in-game chat channel works between
## two REAL peers, with no Steam needed. The host says one thing, the client
## another, and each side prints everything it received; both sides receiving
## both lines is the proof.
##
##   Godot --headless --path <project> res://tests/chat_harness.tscn -- --host
##   Godot --headless --path <project> res://tests/chat_harness.tscn -- --client

const PORT: int = 23458

var _role: String = ""


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_role = "host" if args.has("--host") else "client"
	# Both harness instances share one Steam identity on this box, so label them.
	Chat.set_local_name(_role)
	Chat.message_received.connect(_on_message)
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	if _role == "host":
		peer.create_server(PORT, 4)
		multiplayer.multiplayer_peer = peer
		print("[chat/%s] listening on %d as '%s'" % [_role, PORT, Chat.display_name()])
		await get_tree().create_timer(4.0).timeout
		Chat.say("hello from host")
		await get_tree().create_timer(4.0).timeout
		_finish()
	else:
		peer.create_client("127.0.0.1", PORT)
		multiplayer.multiplayer_peer = peer
		await multiplayer.connected_to_server
		print("[chat/%s] connected as '%s'" % [_role, Chat.display_name()])
		await get_tree().create_timer(1.0).timeout
		Chat.say("hello from client")
		await get_tree().create_timer(6.0).timeout
		_finish()


func _finish() -> void:
	print("[chat/%s] DONE - received %d message(s)" % [_role, Chat.history.size()])
	print("[chat/%s] transcript:\n%s" % [_role, Chat.transcript()])
	get_tree().quit()


func _on_message(from_id: int, from_name: String, text: String) -> void:
	print("[chat/%s] RECEIVED from %d (%s): %s" % [_role, from_id, from_name, text])
