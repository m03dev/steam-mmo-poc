extends Node
## Dev harness (NOT shipped): two REAL peers running the REAL game shell
## (res://scenes/Main.tscn), talking through the in-game Chat channel.
## ENet only, no Steam.
##
##   Godot --headless --path <project> res://tests/game_chat_two_peer.tscn -- --host
##   Godot --headless --path <project> res://tests/game_chat_two_peer.tscn -- --client
##
## Written by Pollux, who proved it on Windows first. Kept here so the Mac side can
## run the same proof: the point is that the shell is the real one, not a stub.

const PORT: int = 23460
const WATCHDOG: float = 40.0

var _role: String = ""
var _done: bool = false


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_role = "host" if args.has("--host") else "client"
	# Never hang, and always flush stdout before exiting.
	get_tree().create_timer(WATCHDOG).timeout.connect(_finish)

	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	if _role == "host":
		peer.create_server(PORT, 4)
		multiplayer.multiplayer_peer = peer
		print("[game/host] listening on %d" % PORT)
	else:
		peer.create_client("127.0.0.1", PORT)
		multiplayer.multiplayer_peer = peer
		await multiplayer.connected_to_server
		print("[game/client] connected, my id=%d" % multiplayer.get_unique_id())

	# Enter the REAL game shell, exactly as the shipped game does.
	# NOTE: add it under this node, not under root -- root is still "busy"
	# setting up children while our _ready() runs, and add_child() to it fails.
	var shell: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(shell)
	await get_tree().create_timer(3.0).timeout
	var names: Array[String] = []
	for c in get_children():
		names.append(c.name)
	print("[game/%s] loaded game shell; children: %s" % [_role, ", ".join(names)])
	print("[game/%s] level holder has %d level(s)" % [_role, shell.get_node("Level").get_child_count()])

	Chat.set_local_name(_role)
	Chat.message_received.connect(_on_message)
	await get_tree().create_timer(1.0).timeout

	if _role == "host":
		var waited: float = 0.0
		while multiplayer.get_peers().is_empty() and waited < 25.0:
			await get_tree().create_timer(0.25).timeout
			waited += 0.25
		print("[game/host] peers: %s (waited %.1fs)" % [str(multiplayer.get_peers()), waited])
		Chat.say("Pollux here: I am in the world, standing next to the trader.")
		await get_tree().create_timer(6.0).timeout
	else:
		Chat.say("Client peer here: I can hear you, I am in the world too.")
		await get_tree().create_timer(6.0).timeout
	_finish()


func _on_message(from_id: int, from_name: String, text: String) -> void:
	print("[game/%s] RECEIVED from %d (%s): %s" % [_role, from_id, from_name, text])


func _finish() -> void:
	if _done:
		return
	_done = true
	print("[game/%s] DONE - %d message(s) in history" % [_role, Chat.history.size()])
	print("[game/%s] transcript:" % _role)
	print(Chat.transcript())
	get_tree().quit()