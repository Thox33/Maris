extends Node2D
## Main scene — active once a network connection is established.
## The server initializes the world and waits for clients (including itself
## when not running in dedicated mode). All players join through the same
## _client_ready path — the host is no longer a special case.

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const ITEM_ENTITY_SCENE := preload("res://scenes/items/item_entity.tscn")

## Default world name. Will support selection from lobby UI in the future.
const DEFAULT_WORLD_NAME: String = "default"

## Fixed spawn position in tile-space (converted to pixels on spawn).
const SPAWN_TILE := Vector2i(0, 4)

@onready var world: Node2D = $World
@onready var _player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var _item_spawner: MultiplayerSpawner = $ItemSpawner
@onready var inventory_manager: Node = $InventoryManager

## Set to true before loading this scene to run a playerless server.
static var dedicated_server: bool = false

var _is_app_quitting: bool = false


func _ready() -> void:
	_player_spawner.spawn_function = _create_player
	_item_spawner.spawn_function = _create_item_entity
	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	NetworkManager.session_ended.connect(_on_session_ended)
	GameEvents.game_leaving.connect(_on_game_leaving)
	GameEvents.block_broken.connect(_on_block_broken)
	get_tree().auto_accept_quit = false

	# Give InventoryManager references it needs.
	inventory_manager.item_spawner = _item_spawner
	inventory_manager.chunk_manager = world.chunk_manager

	if multiplayer.is_server():
		SaveManager.set_world(DEFAULT_WORLD_NAME)
		SaveManager.auto_save_requested.connect(_on_auto_save)

		var seed_value: int = _load_or_create_seed()
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

	var player_id := str(peer_id)
	var saved := SaveManager.load_player(player_id)

	# Determine spawn position — use saved position if available.
	var pos := _get_spawn_position()
	if saved.has("x") and saved.has("y"):
		pos = Vector2(saved["x"], saved["y"])

	# Ensure terrain exists before the player lands.
	world.chunk_manager.load_chunks_around(pos)

	# Spawn the player (MultiplayerSpawner replicates to all peers).
	if not $Players.has_node(player_id):
		_player_spawner.spawn({"peer_id": peer_id, "x": pos.x, "y": pos.y})

	# Create inventory and restore saved items if available.
	inventory_manager.create_inventory(peer_id)
	if saved.has("inventory"):
		_restore_inventory(peer_id, saved["inventory"])

	GameEvents.player_joined.emit(peer_id)


func _on_player_disconnected(peer_id: int) -> void:
	GameEvents.player_left.emit(peer_id)
	# Save player state before cleanup.
	_save_player(peer_id)
	# Clean up inventory.
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


## Handles item drops when a block is broken. Listens to GameEvents.block_broken.
func _on_block_broken(coord: Vector2i, tile_id: int) -> void:
	if not multiplayer.is_server():
		return
	var props := TileProperties.get_properties(tile_id)
	if props == null:
		return
	var drop_id: int = props.drop_tile_id if props else tile_id
	var item_id: int = ItemProperties.from_tile(drop_id)
	if item_id == ItemProperties.NONE:
		return
	var tile_center := Vector2(
		coord.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
		coord.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
	)
	spawn_item_drop(item_id, 1, tile_center)


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


# --- Persistence helpers ---


## Returns the saved seed or generates a new one for a fresh world.
func _load_or_create_seed() -> int:
	var meta := SaveManager.load_world_meta()
	if meta.has("seed"):
		print("[Main] Loaded existing world '%s'" % DEFAULT_WORLD_NAME)
		return int(meta["seed"])
	var new_seed: int = randi()
	SaveManager.save_world_meta(new_seed)
	print("[Main] Created new world '%s'" % DEFAULT_WORLD_NAME)
	return new_seed


## Serializes a player's current state and writes it to disk.
func _save_player(peer_id: int) -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	var player_id := str(peer_id)
	var data: Dictionary = {}

	# Position from the player node.
	var player_node := $Players.get_node_or_null(player_id)
	if player_node:
		data["x"] = player_node.global_position.x
		data["y"] = player_node.global_position.y

	# Inventory.
	var inv: Inventory = inventory_manager.get_inventory(peer_id)
	if inv:
		data["inventory"] = inv.serialize()

	SaveManager.save_player(player_id, data)
	print("[Main] Saved player %s" % player_id)


## Restores inventory from saved data into the already-created inventory,
## then re-syncs to the owning client.
func _restore_inventory(peer_id: int, saved_slots: Array) -> void:
	var inv: Inventory = inventory_manager.get_inventory(peer_id)
	if inv == null:
		return
	for i in range(mini(saved_slots.size(), inv.size)):
		var slot: Dictionary = saved_slots[i]
		inv.set_slot(i, slot.get("item_id", ItemProperties.NONE), slot.get("count", 0))
	inventory_manager.sync_inventory(peer_id)


## Saves all world state: chunks, players, world meta.
func _save_world() -> void:
	if multiplayer.multiplayer_peer == null or not multiplayer.is_server():
		return
	SaveManager.save_world_meta(world.world_seed)
	SaveManager.save_all_chunks(world.chunk_manager.loaded_chunks)
	# Save all connected players.
	for player in $Players.get_children():
		var peer_id: int = player.name.to_int()
		if peer_id > 0:
			_save_player(peer_id)
	print("[Main] World saved")


func _on_auto_save() -> void:
	_save_world()


## Fired by GameEvents.game_leaving BEFORE the peer closes.
## Covers all leave paths: user_left, connection_lost, app_quit.
func _on_game_leaving() -> void:
	_save_world()


func _on_session_ended(reason: String) -> void:
	if reason == "app_quit":
		get_tree().quit()


func _exit_tree() -> void:
	get_tree().auto_accept_quit = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _is_app_quitting:
			return
		_is_app_quitting = true
		NetworkManager.leave_game("app_quit")
