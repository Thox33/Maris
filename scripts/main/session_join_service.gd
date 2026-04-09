extends Node

## Owns the session join flow and join-related RPC entrypoints.

var world: Node2D
var identity_service: Node
var character_setup_service: Node
var player_spawn_service: Node


func setup(
	p_world: Node2D, p_identity_service: Node, p_character_setup_service: Node, p_player_spawn_service: Node
) -> void:
	world = p_world
	identity_service = p_identity_service
	character_setup_service = p_character_setup_service
	player_spawn_service = p_player_spawn_service


func send_client_ready() -> void:
	_client_ready.rpc_id(1, ClientProfile.get_account_id(), ClientProfile.display_name)


func server_handle_join(peer_id: int, account_id: String, display_name: String) -> void:
	if not multiplayer.is_server():
		return

	var safe_name := _sanitize_display_name(display_name, peer_id)
	identity_service.register_peer(peer_id, account_id, safe_name)

	var player_record := SaveManager.load_player(account_id)
	if not SaveManager.has_character(account_id):
		character_setup_service.begin_for_peer(peer_id, account_id, safe_name)
		return

	player_spawn_service.complete_join(peer_id, player_record)


func reject_join(peer_id: int, reason: String) -> void:
	print("[SessionJoinService] Rejecting join for peer %d: %s" % [peer_id, reason])
	push_error("[SessionJoinService] Rejected join from peer %d: %s" % [peer_id, reason])
	_join_rejected.rpc_id(peer_id, reason)


@rpc("any_peer", "reliable")
func _client_ready(account_id: String, display_name: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()
	if not ClientProfile.is_valid_account_id(account_id):
		reject_join(sender_id, "Invalid client identity.")
		return

	if identity_service.has_duplicate_account(account_id):
		reject_join(sender_id, "This player identity is already connected.")
		return

	var safe_name := _sanitize_display_name(display_name, sender_id)
	_receive_world_seed.rpc_id(sender_id, world.world_seed)
	server_handle_join(sender_id, account_id, safe_name)


@rpc("authority", "reliable")
func _join_rejected(reason: String) -> void:
	if multiplayer.is_server():
		return

	print("[SessionJoinService] Join rejected by host: %s" % reason)
	push_warning("[SessionJoinService] Join rejected: %s" % reason)
	NetworkManager.leave_game("connection_failed")


@rpc("authority", "reliable")
func _receive_world_seed(seed_value: int) -> void:
	world.initialize(seed_value)
	world.chunk_manager.load_chunks_around(player_spawn_service.get_spawn_position())


func _sanitize_display_name(display_name: String, peer_id: int) -> String:
	var safe_name := display_name.strip_edges().left(32)
	if safe_name.is_empty():
		safe_name = "Player_%d" % peer_id
	return safe_name
