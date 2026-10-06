extends Node
## Networking (autoload "Net"). One player hosts: their game runs the
## authoritative World and an ENet server. Friends join it as clients.
## Clients only send requests; every rule runs on the host, which sends
## events back. The host's own player talks to the World directly.

signal event(ev: Dictionary)          # an event for this player's view
signal joined(map_name: String)
signal failed(reason: String)
signal closed(reason: String)

const PROTOCOL := 1
const DEFAULT_PORT := 24680
const MAX_PEERS := 16

var world: World = null
var is_host := false
var my_peer := 0
var world_name := ""
var _password := ""
var _hello := {}
var _accum := 0.0
var _joined := {}      # peers that are in the world


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("Could not reach the host."))
	multiplayer.server_disconnected.connect(func(): _close("The host closed the world."))
	get_tree().set_auto_accept_quit(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		stop()
		get_tree().quit()


static func identity() -> String:
	## This installation's secret: it proves a character is ours on a host.
	var path := "user://identity.json"
	var data = Save.read_json(path)
	if typeof(data) == TYPE_DICTIONARY and data.has("token"):
		return data.token
	var crypto := Crypto.new()
	var token := crypto.generate_random_bytes(16).hex_encode()
	Save.write_json(path, {"token": token})
	return token


static func world_dir(name: String) -> String:
	return "user://worlds/%s" % name.to_lower().replace(" ", "_")


## Host a world (created on first use) and enter it as char_name.
func host(name: String, password: String, port: int, char_name: String) -> String:
	stop()
	if not World.valid_name(name):
		return "World names are 2-20 letters, digits, spaces or dashes."
	var dir := world_dir(name)
	DirAccess.make_dir_recursive_absolute(dir)
	var meta = Save.read_json(dir + "/world.json")
	if typeof(meta) != TYPE_DICTIONARY:
		meta = {"name": name, "created": Time.get_datetime_string_from_system()}
	meta.password = password
	Save.write_json(dir + "/world.json", meta)
	world = World.new()
	if not world.errors.is_empty():
		var why := "World data is broken: " + "; ".join(world.errors)
		world = null
		return why
	world.save_dir = dir
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PEERS)
	if err != OK:
		world = null
		return "Could not open port %d (%s). Is another world running?" % [port, error_string(err)]
	multiplayer.multiplayer_peer = peer
	is_host = true
	my_peer = 1
	world_name = name
	_password = password
	var why := world.join(1, char_name, identity())
	if why != "":
		stop()
		return why
	_joined[1] = true
	joined.emit(world.map.name)
	_pump()
	return ""


## Join a friend's world.
func join(address: String, port: int, password: String, char_name: String) -> String:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return "Could not connect to %s:%d (%s)." % [address, port, error_string(err)]
	multiplayer.multiplayer_peer = peer
	is_host = false
	_hello = {"protocol": PROTOCOL, "name": char_name, "secret": identity(), "password": password}
	return ""


func stop() -> void:
	if world:
		world.save_all()
	world = null
	is_host = false
	my_peer = 0
	_joined.clear()
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func active() -> bool:
	return my_peer != 0


## A request from this player to the World.
func request(req: Dictionary) -> void:
	if is_host and world:
		world.handle(1, req)
	elif my_peer:
		_req.rpc_id(1, req)


func _process(delta: float) -> void:
	if not is_host or world == null:
		return
	_accum += delta * 1000.0
	var ms := int(_accum)
	if ms <= 0:
		return
	_accum -= ms
	world.tick(ms)
	_pump()


## Deliver the World's events: ours locally, others' over the network.
func _pump() -> void:
	var batches := {}
	for ev in world.drain():
		var to: int = ev.get("to", 0)
		if to:
			if to == 1:
				event.emit(ev)
			elif _joined.has(to):
				batches.get_or_add(to, []).append(ev)
		else:
			event.emit(ev)
			for peer in _joined:
				if peer != 1:
					batches.get_or_add(peer, []).append(ev)
	for peer in batches:
		_events.rpc_id(peer, batches[peer])


# --------------------------------------------------------------------------
# Host side

func _on_peer_connected(id: int) -> void:
	pass    # they introduce themselves with _hello


func _on_peer_disconnected(id: int) -> void:
	if is_host and world and _joined.has(id):
		_joined.erase(id)
		world.leave(id)
		_pump()


@rpc("any_peer", "call_remote", "reliable")
func _say_hello(hello: Dictionary) -> void:
	if not is_host or world == null:
		return
	var id := multiplayer.get_remote_sender_id()
	var why := ""
	if int(hello.get("protocol", 0)) != PROTOCOL:
		why = "This world runs a different version of Aethyra."
	elif str(hello.get("password", "")) != _password:
		why = "Wrong world password."
	else:
		why = world.join(id, str(hello.get("name", "")), str(hello.get("secret", "")))
	if why != "":
		_refused.rpc_id(id, why)
		get_tree().create_timer(1.0).timeout.connect(func():
			if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
				multiplayer.multiplayer_peer.disconnect_peer(id))
		return
	_joined[id] = true
	_pump()


@rpc("any_peer", "call_remote", "reliable")
func _req(req: Dictionary) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_host and world and _joined.has(id) and typeof(req) == TYPE_DICTIONARY:
		world.handle(id, req)


# --------------------------------------------------------------------------
# Client side

func _on_connected() -> void:
	my_peer = multiplayer.get_unique_id()
	_say_hello.rpc_id(1, _hello)


@rpc("authority", "call_remote", "reliable")
func _events(batch: Array) -> void:
	for ev in batch:
		ev = Save.ints(ev)
		if ev.t == "welcome":
			joined.emit(ev.map)
		event.emit(ev)


@rpc("authority", "call_remote", "reliable")
func _refused(reason: String) -> void:
	_fail(reason)


func _fail(reason: String) -> void:
	stop()
	failed.emit(reason)


func _close(reason: String) -> void:
	stop()
	closed.emit(reason)
