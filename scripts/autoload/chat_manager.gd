extends Node
## Central chat manager. Autoloaded as "ChatManager".
## Bridges client input to server-side processing and distributes messages back.
## Commands (text starting with "/") are routed to CommandRegistry on the server.

var is_chat_open: bool = false
var commands: CommandRegistry
var _session_world: Node
var _session_players: Node
var _session_inventory_manager: Node

signal message_received(msg: Dictionary)


func _ready() -> void:
	commands = CommandRegistry.new()
	commands.register("help", "Show all available commands.", _cmd_help)
	commands.register("tp", "Teleport yourself to tile coordinates: /tp <x> <y>", _cmd_tp)
	commands.register(
		"teleport",
		"Teleport yourself to tile coordinates: /teleport <x> <y>",
		_cmd_tp
	)
	commands.register(
		"give",
		"Give items: /give <item> [count] or /give <player> <item> <count>",
		_cmd_give
	)
	NetworkManager.session_ended.connect(_on_session_ended)
	GameEvents.player_joined.connect(_on_player_joined)
	GameEvents.player_left.connect(_on_player_left)


## Called by ChatUI when the local player submits a message.
func submit(text: String) -> void:
	text = text.strip_edges()
	if text.is_empty():
		return
	if text.length() > GameConstants.MAX_CHAT_LENGTH:
		text = text.left(GameConstants.MAX_CHAT_LENGTH)
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_process_on_server(multiplayer.get_unique_id(), text)
	else:
		_submit_message.rpc_id(1, text)


func open_chat() -> void:
	is_chat_open = true


func close_chat() -> void:
	is_chat_open = false


func set_session_context(world: Node, players_node: Node, inventory_manager: Node) -> void:
	_session_world = world
	_session_players = players_node
	_session_inventory_manager = inventory_manager


func clear_session_context() -> void:
	_session_world = null
	_session_players = null
	_session_inventory_manager = null


func _on_session_ended(_reason: String) -> void:
	close_chat()
	clear_session_context()


## Client -> Server: deliver raw text for server-side processing.
@rpc("any_peer", "reliable")
func _submit_message(text: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	text = text.strip_edges()
	if text.is_empty() or text.length() > GameConstants.MAX_CHAT_LENGTH:
		return
	_process_on_server(sender_id, text)


func _process_on_server(sender_id: int, text: String) -> void:
	if text.begins_with("/"):
		_process_command(sender_id, text.substr(1))
		return
	var msg := {
		"type": "player",
		"sender_peer_id": sender_id,
		"sender_display_name": NetworkManager.get_player_visible_name(sender_id),
		"text": text,
	}
	_receive_message.rpc(msg)
	message_received.emit(msg)


func _process_command(sender_id: int, raw: String) -> void:
	var parts := raw.split(" ", false)
	if parts.is_empty():
		return
	var name: String = parts[0]
	var args: Array[String] = []
	for i: int in range(1, parts.size()):
		args.append(parts[i])
	var lines: Array[String] = commands.execute(sender_id, name, args)
	for line: String in lines:
		_send_system_to_peer(sender_id, line)


func _send_system_to_peer(peer_id: int, text: String) -> void:
	var msg := {"type": "system", "sender_peer_id": 0, "text": text}
	if peer_id == multiplayer.get_unique_id():
		message_received.emit(msg)
	else:
		_receive_message.rpc_id(peer_id, msg)


func _broadcast_system(text: String) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var msg := {"type": "system", "sender_peer_id": 0, "text": text}
	_receive_message.rpc(msg)
	message_received.emit(msg)


## Server -> all clients (or a specific peer via rpc_id): deliver a message for display.
@rpc("authority", "reliable")
func _receive_message(msg: Dictionary) -> void:
	message_received.emit(msg)


func _on_player_joined(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	_broadcast_system("%s joined the game." % NetworkManager.get_player_visible_name(peer_id))


func _on_player_left(_peer_id: int, visible_name: String) -> void:
	if not multiplayer.is_server():
		return
	_broadcast_system("%s left the game." % visible_name)


func _cmd_help(_sender_id: int, _args: Array[String]) -> Array[String]:
	return commands.get_help_lines()


func _cmd_tp(sender_id: int, args: Array[String]) -> Array[String]:
	if args.size() != 2:
		return ["Usage: /tp <x> <y>"]

	if not args[0].is_valid_int() or not args[1].is_valid_int():
		return ["Teleport coordinates must be integers."]

	var players := _session_players
	if players == null:
		return ["Teleport failed: players container not found."]

	var player := players.get_node_or_null(str(sender_id)) as CharacterBody2D
	if player == null:
		return ["Teleport failed: player not found."]

	var tile_x := args[0].to_int()
	var tile_y := args[1].to_int()
	var world_pos := Vector2(
		tile_x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
		tile_y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
	)

	var world := _session_world
	if world != null:
		var chunk_manager := world.get_node_or_null("ChunkManager")
		if chunk_manager != null:
			chunk_manager.load_chunks_around(world_pos)

	player.global_position = world_pos
	player.velocity = Vector2.ZERO
	if player.has_method("apply_server_teleport"):
		player.apply_server_teleport(world_pos)

	return ["Teleported to (%d, %d)." % [tile_x, tile_y]]


func _cmd_give(sender_id: int, args: Array[String]) -> Array[String]:
	if args.is_empty():
		return ["Usage: /give <item> [count] or /give <player> <item> <count>"]

	var target_peer_id := sender_id
	var item_name := ""
	var count := 1

	if args.size() == 1:
		item_name = args[0]
	elif args.size() == 2:
		item_name = args[0]
		if not args[1].is_valid_int():
			return ["Count must be an integer."]
		count = args[1].to_int()
	else:
		var count_arg := args[args.size() - 1]
		if not count_arg.is_valid_int():
			return ["Count must be an integer."]
		count = count_arg.to_int()
		item_name = args[args.size() - 2]
		var player_name := " ".join(args.slice(0, args.size() - 2))
		target_peer_id = _find_peer_id_by_visible_name(player_name)
		if target_peer_id <= 0:
			return ["Player not found: %s" % player_name]

	if count <= 0:
		return ["Count must be greater than zero."]

	var item_id := ItemProperties.by_name.get(item_name.to_lower(), ItemProperties.NONE) as int
	if item_id == ItemProperties.NONE:
		return ["Unknown item: %s" % item_name]

	var inventory_manager := _session_inventory_manager
	if inventory_manager == null:
		return ["Give failed: inventory manager not found."]

	var remainder: int = inventory_manager.server_add_item(target_peer_id, item_id, count)
	var given_count := count - remainder
	if given_count <= 0:
		return ["Could not give %s. Inventory is full." % item_name]

	var target_name := NetworkManager.get_player_visible_name(target_peer_id)
	if remainder > 0:
		return [
			"Gave %d %s to %s (%d did not fit)." % [given_count, item_name, target_name, remainder]
		]

	return ["Gave %d %s to %s." % [given_count, item_name, target_name]]


func _find_peer_id_by_visible_name(player_name: String) -> int:
	var wanted := player_name.strip_edges().to_lower()
	if wanted.is_empty():
		return 0

	for peer_id_variant in NetworkManager.players.keys():
		var peer_id := int(peer_id_variant)
		if NetworkManager.get_player_visible_name(peer_id).to_lower() == wanted:
			return peer_id

	return 0
