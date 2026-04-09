extends Node

## Boots the world/session once the main scene has been composed.

var world: Node2D
var persistence_service: Node
var player_spawn_service: Node
var join_service: Node


func setup(
	p_world: Node2D, p_persistence_service: Node, p_player_spawn_service: Node, p_join_service: Node
) -> void:
	world = p_world
	persistence_service = p_persistence_service
	player_spawn_service = p_player_spawn_service
	join_service = p_join_service


func bootstrap_session(world_name: String, dedicated_server: bool) -> void:
	if multiplayer.is_server():
		persistence_service.activate_world(world_name)
		var seed_value: int = persistence_service.load_or_create_seed()
		print("[SessionBootstrapService] Initializing world '%s' with seed %d" % [world_name, seed_value])
		world.initialize(seed_value)
		world.structure_manager.load_from_save()

		if dedicated_server:
			world.chunk_manager.load_chunks_around(player_spawn_service.get_spawn_position())
			print("[SessionBootstrapService] Running as dedicated server (no local player)")
		else:
			join_service.server_handle_join(
				multiplayer.get_unique_id(), ClientProfile.get_account_id(), ClientProfile.display_name
			)
	else:
		join_service.send_client_ready()
