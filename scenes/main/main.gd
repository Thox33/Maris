extends Node2D
## Main scene — active once a network connection is established.
## The server initializes the world and waits for clients (including itself
## when not running in dedicated mode). All players join through the same
## _client_ready path — the host is no longer a special case.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ITEM_ENTITY_SCENE := preload("res://scenes/items/item_entity.tscn")

## Fixed spawn position in tile-space (converted to pixels on spawn).
const SPAWN_TILE := Vector2i(0, 4)

@onready var world: Node2D = $World
@onready var _player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _item_spawner: MultiplayerSpawner = $ItemSpawner
@onready var inventory_manager: Node = $InventoryManager

## Set to true before loading this scene to run a playerless server.
static var dedicated_server: bool = false


func _ready() -> void:
	_player_spawner.spawn_function = _create_player
	_item_spawner.spawn_function = _create_item_entity
	NetworkManager.player_disconnected.connect(_on_player_disconnected)

	# Give InventoryManager references it needs.
	inventory_manager.item_spawner = _item_spawner
	inventory_manager.chunk_manager = world.chunk_manager

	if multiplayer.is_server():
		var seed_value: int = randi()
		print("[Main] Initializing world with seed %d" % seed_value)
		world.initialize(seed_value)

		if dedicated_server:
			# Dedicated server: load spawn area but don't join as a player.
			world.chunk_manager.load_chunks_around(_get_spawn_position())
			print("[Main] Running as dedicated server (no local player)")
		else:
			# Host-as-player: join through the same path as any client.
			_server_handle_join(multiplayer.get_unique_id())
	else:
		_client_ready.rpc_id(1)


# --- Player spawning ---


## Creates a player node from spawn data — called on all peers by the spawner.
func _create_player(data: Dictionary) -> Node:
	var player := PLAYER_SCENE.instantiate()
	player.name = str(data["peer_id"])
	player.position = Vector2(data["x"], data["y"])
	player.set_multiplayer_authority(data["peer_id"])
	player.add_to_group("players")
	return player


## Server-only: full join sequence for a new player.
func _server_handle_join(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Ensure terrain exists around spawn before the player lands.
	var pos := _get_spawn_position()
	world.chunk_manager.load_chunks_around(pos)
	# Spawn the player (MultiplayerSpawner replicates to all peers).
	if not $Players.has_node(str(peer_id)):
		_player_spawner.spawn({"peer_id": peer_id, "x": pos.x, "y": pos.y})
	# Create an inventory for this player and sync it.
	inventory_manager.create_inventory(peer_id)


func _on_player_disconnected(peer_id: int) -> void:
	# Clean up inventory (could persist to disk here in the future).
	inventory_manager.remove_inventory(peer_id)
	# queue_free on a spawner-tracked node automatically despawns on all peers.
	var node := $Players.get_node_or_null(str(peer_id))
	if node:
		node.queue_free()


# --- Item entity spawning ---


## Creates an item entity from spawn data — called on all peers by the spawner.
func _create_item_entity(data: Dictionary) -> Node:
	var entity := ITEM_ENTITY_SCENE.instantiate()
	entity.initialize(data["item_id"], data["count"])
	entity.position = Vector2(data["x"], data["y"])
	return entity


## Server-only: spawns an item drop in the world at the given position.
func spawn_item_drop(item_id: int, count: int, world_pos: Vector2) -> void:
	if not multiplayer.is_server():
		return
	_item_spawner.spawn({
		"item_id": item_id,
		"count": count,
		"x": world_pos.x,
		"y": world_pos.y,
	})


# --- Client join RPC ---


## Client calls this when the main scene is loaded and ready.
@rpc("any_peer", "reliable")
func _client_ready() -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	_receive_world_seed.rpc_id(sender_id, world.world_seed)
	_server_handle_join(sender_id)


## Client receives the world seed and initializes terrain.
@rpc("authority", "reliable")
func _receive_world_seed(seed_value: int) -> void:
	world.initialize(seed_value)
	world.chunk_manager.load_chunks_around(_get_spawn_position())


func _get_spawn_position() -> Vector2:
	return Vector2(
		SPAWN_TILE.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
		SPAWN_TILE.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
	)
