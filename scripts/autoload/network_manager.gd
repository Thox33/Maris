extends Node
## Manages multiplayer connections using Godot's built-in MultiplayerAPI.
## Autoloaded as "NetworkManager".
##
## Architecture: Host-as-server model. One player creates the game (host),
## other players join. The host is both server and client (peer id 1).

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal connection_succeeded
signal connection_failed
signal server_disconnected
signal ping_updated(ping_ms: float)
## Emitted after the session shutdown path ran local cleanup and closed the peer.
## reason: "user_left" | "connection_lost" | "connection_failed" | "app_quit"
signal session_ended(reason: String)

## Stores connected player info. Key = peer_id, Value = player data dict.
var players: Dictionary = {}
var ping_ms: float = 0.0

var _ping_timer: float = 0.0
var _next_ping_id: int = 1
var _pending_pings: Dictionary = {}
var _is_leaving: bool = false


func _ready() -> void:
	# Connect multiplayer signals so we get notified about connections.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return

	if multiplayer.is_server():
		if ping_ms != 0.0:
			ping_ms = 0.0
			ping_updated.emit(ping_ms)
		return

	_ping_timer += delta
	if _ping_timer >= 1.0:
		_ping_timer = 0.0
		_send_ping()


## Host a game. Creates an ENetMultiplayerPeer as server.
func host_game(port: int = GameConstants.DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, GameConstants.MAX_PLAYERS)
	if error != OK:
		push_error("Failed to create server: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	players[1] = {}  # Host is always peer id 1
	print("Hosting game on port %d" % port)
	return OK


## Join an existing game.
func join_game(address: String = "127.0.0.1", port: int = GameConstants.DEFAULT_PORT) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		push_error("Failed to create client: %s" % error_string(error))
		return error
	multiplayer.multiplayer_peer = peer
	_ping_timer = 0.0
	_pending_pings.clear()
	print("Joining game at %s:%d" % [address, port])
	return OK


func leave_game(reason: String = "user_left") -> void:
	if _is_leaving:
		return
	_is_leaving = true
	GameEvents.game_leaving.emit()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	ping_ms = 0.0
	_ping_timer = 0.0
	_pending_pings.clear()
	_is_leaving = false
	session_ended.emit(reason)


func _on_peer_connected(id: int) -> void:
	players[id] = {}
	player_connected.emit(id)
	print("Player connected: %d" % id)


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	player_disconnected.emit(id)
	print("Player disconnected: %d" % id)


func _on_connected_to_server() -> void:
	connection_succeeded.emit()
	_send_ping()
	print("Successfully connected to server")


func _on_connection_failed() -> void:
	leave_game("connection_failed")
	connection_failed.emit()
	push_warning("Connection to server failed")


func _on_server_disconnected() -> void:
	leave_game("connection_lost")
	server_disconnected.emit()
	push_warning("Disconnected from server")


func _send_ping() -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.is_server():
		return

	var ping_id := _next_ping_id
	_next_ping_id += 1
	_pending_pings[ping_id] = Time.get_ticks_usec()
	_ping_server.rpc_id(1, ping_id)


@rpc("any_peer", "unreliable")
func _ping_server(ping_id: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	_pong_client.rpc_id(sender_id, ping_id)


@rpc("authority", "unreliable")
func _pong_client(ping_id: int) -> void:
	if multiplayer.is_server():
		return

	if not _pending_pings.has(ping_id):
		return

	var sent_usec: int = _pending_pings[ping_id]
	_pending_pings.erase(ping_id)
	ping_ms = (Time.get_ticks_usec() - sent_usec) / 1000.0
	ping_updated.emit(ping_ms)
