extends Node
## Autoload "Chat" - one in-game text channel over the high-level multiplayer.
## Uses only @rpc, so it works on any transport (Steam SDR or plain ENet): the
## node path is identical on every peer (/root/Chat), which is all Godot's RPC
## layer needs. Messages are printed as well as emitted, so a headless peer can
## speak (Chat.say) and observe (Chat.message_received) with no UI at all.

signal message_received(from_id: int, from_name: String, text: String)
signal system_message(text: String)

const MAX_LEN: int = 256
const HISTORY_MAX: int = 200

var history: Array[Dictionary] = []
var local_name: String = "player"
## Explicit label for this peer. Overrides the Steam persona; dev harnesses and
## agent peers use it when the transport carries no meaningful identity.
var name_override: String = ""


func _ready() -> void:
	local_name = display_name()


## Label this peer explicitly. Empty string restores the automatic name.
func set_local_name(n: String) -> void:
	name_override = n.strip_edges()


## Who this peer speaks as. Read live, because Steam can finish signing in
## after this node is ready.
func display_name() -> String:
	if name_override != "":
		return name_override
	if Engine.has_singleton("Steam") and SteamManager.is_initialized:
		var p: String = SteamManager.persona_name.strip_edges()
		if not p.is_empty():
			return p
	return local_name if local_name != "" else "peer_%d" % multiplayer.get_unique_id()


## Say something to every peer. With no peers yet the local copy still lands
## (call_local), so nothing is silently dropped before the session is up.
func say(text: String) -> void:
	var t: String = _clean(text)
	if t.is_empty():
		return
	if multiplayer.multiplayer_peer == null:
		# No transport yet: deliver locally so the message is not lost or an
		# RPC error is raised before the session exists.
		_deliver(display_name(), t)
		return
	_deliver.rpc(display_name(), t)


## Say something to one peer only.
func say_to(peer_id: int, text: String) -> void:
	var t: String = _clean(text)
	if t.is_empty():
		return
	if multiplayer.multiplayer_peer == null:
		_deliver(display_name(), t)
		return
	_deliver.rpc_id(peer_id, display_name(), t)


## The whole channel so far, as one string (for a HUD or a log dump).
func transcript() -> String:
	var lines: PackedStringArray = []
	for r: Dictionary in history:
		lines.append("<%s> %s" % [str(r["name"]), str(r["text"])])
	return "\n".join(lines)


func _clean(text: String) -> String:
	var t: String = text.strip_edges()
	if t.length() > MAX_LEN:
		t = t.substr(0, MAX_LEN)
	return t


@rpc("any_peer", "call_local", "reliable")
func _deliver(from_name: String, text: String) -> void:
	# The speaker is whoever the transport says it is - a caller-supplied id is
	# never trusted, so no peer can speak as another.
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = multiplayer.get_unique_id()
	history.append({"id": sender, "name": from_name, "text": text})
	while history.size() > HISTORY_MAX:
		history.remove_at(0)
	print("[Chat] <%s> %s" % [from_name, text])
	message_received.emit(sender, from_name, text)
