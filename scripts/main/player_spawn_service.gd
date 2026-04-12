extends Node

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const CHARACTER_APPEARANCE := preload("res://scripts/actor/character_appearance.gd")
const SPAWN_SEARCH_X := 0
const SPAWN_SEARCH_Y_RANGE := 40

var world: Node2D
var players_node: Node
var items_node: Node
var player_spawner: MultiplayerSpawner
var inventory_manager: Node
var use_authority_service: Node
var identity_service: Node
var character_setup_service: Node
var persistence_service: Node

var _is_initialized: bool = false


func setup(
	p_world: Node2D,
	p_players_node: Node,
	p_items_node: Node,
	p_player_spawner: MultiplayerSpawner,
	p_inventory_manager: Node,
	p_use_authority_service: Node,
	p_identity_service: Node,
	p_character_setup_service: Node,
	p_persistence_service: Node
) -> void:
	world = p_world
	players_node = p_players_node
	items_node = p_items_node
	player_spawner = p_player_spawner
	inventory_manager = p_inventory_manager
	use_authority_service = p_use_authority_service
	identity_service = p_identity_service
	character_setup_service = p_character_setup_service
	persistence_service = p_persistence_service

	if _is_initialized:
		return

	NetworkManager.player_disconnected.connect(_on_player_disconnected)
	_is_initialized = true


func create_player(data: Dictionary) -> Node:
	var player := PLAYER_SCENE.instantiate()
	var appearance := CHARACTER_APPEARANCE.normalize_appearance(data.get("appearance", {}))
	player.name = str(data["peer_id"])
	player.position = Vector2(data["x"], data["y"])
	player.set_multiplayer_authority(data["peer_id"])
	player.add_to_group("players")
	if player.has_method("setup_session"):
		player.setup_session(
			inventory_manager,
			items_node,
			players_node,
			world.terrain_layer,
			world.chunk_manager,
			world.structure_manager,
			use_authority_service,
			world.chunk_debug_overlay
		)
	player.apply_character_data(String(data.get("character_name", "")), appearance)
	return player


func get_spawn_position() -> Vector2:
	return _find_clear_spawn()


## Scans downward from (SPAWN_SEARCH_X, 0) for a cell with solid ground and no top tile.
## Assumes chunks around the origin are already loaded.
func _find_clear_spawn() -> Vector2:
	var cm: Node = world.chunk_manager if world != null else null
	if cm != null:
		for y in range(-SPAWN_SEARCH_Y_RANGE, SPAWN_SEARCH_Y_RANGE):
			var coord := Vector2i(SPAWN_SEARCH_X, y)
			var ground_id: int = cm.get_ground_tile_at(coord)
			var ground_props := GroundTileProperties.get_properties(ground_id)
			if ground_props != null and ground_props.is_solid:
				if cm.get_top_tile_at(coord) == TileProperties.EMPTY:
					return Vector2(
						coord.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
						coord.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0
					)
	# Fallback: origin.
	return Vector2(GameConstants.TILE_SIZE / 2.0, GameConstants.TILE_SIZE / 2.0)


func complete_join(peer_id: int, player_record: Dictionary) -> void:
	if not multiplayer.is_server():
		return

	var safe_name := String(identity_service.get_display_name(peer_id))
	NetworkManager.set_player_display_name(peer_id, safe_name)

	var progress := SaveManager.get_progress_record(player_record)
	var character := SaveManager.get_character_record(player_record)
	var character_name := String(character.get("name", ""))
	var appearance := CHARACTER_APPEARANCE.normalize_appearance(character.get("appearance", {}))
	NetworkManager.set_player_character_name(peer_id, character_name)

	var pos: Vector2
	if progress.has("x") and progress.has("y"):
		pos = Vector2(progress["x"], progress["y"])
		world.chunk_manager.load_chunks_around(pos)
	else:
		# Load chunks around origin first so the spawn scan has tile data available.
		var origin := Vector2(GameConstants.TILE_SIZE / 2.0, GameConstants.TILE_SIZE / 2.0)
		world.chunk_manager.load_chunks_around(origin)
		pos = get_spawn_position()
	world.structure_manager.sync_full_state_to_peer(peer_id)

	var player_id := str(peer_id)
	if not players_node.has_node(player_id):
		player_spawner.spawn(
			{
				"peer_id": peer_id,
				"x": pos.x,
				"y": pos.y,
				"character_name": character_name,
				"appearance": appearance,
			}
		)

	inventory_manager.create_inventory(peer_id)
	if progress.has("inventory"):
		_restore_inventory(peer_id, progress["inventory"])

	character_setup_service.clear_pending(peer_id)
	identity_service.broadcast_player_identities()
	GameEvents.player_joined.emit(peer_id)


func _restore_inventory(peer_id: int, saved_slots: Array) -> void:
	var inv: Inventory = inventory_manager.get_inventory(peer_id)
	if inv == null:
		return
	for i in range(mini(saved_slots.size(), inv.size)):
		var slot: Dictionary = saved_slots[i]
		inv.set_slot(i, slot.get("item_id", ItemProperties.NONE), slot.get("count", 0))
	inventory_manager.sync_inventory(peer_id)


func _on_player_disconnected(peer_id: int) -> void:
	var visible_name := _get_disconnect_visible_name(peer_id)
	GameEvents.player_left.emit(peer_id, visible_name)
	persistence_service.save_player(peer_id)
	identity_service.remove_peer(peer_id)
	character_setup_service.discard_peer(peer_id)
	identity_service.broadcast_player_identities()
	inventory_manager.remove_inventory(peer_id)

	var node := players_node.get_node_or_null(str(peer_id))
	if node != null:
		node.queue_free()


func _get_disconnect_visible_name(peer_id: int) -> String:
	var account_id := String(identity_service.get_account_id(peer_id))
	if not account_id.is_empty():
		var record := SaveManager.load_player(account_id)
		var character := SaveManager.get_character_record(record)
		var character_name := String(character.get("name", "")).strip_edges()
		if not character_name.is_empty():
			return character_name

	var display_name := String(identity_service.get_display_name(peer_id)).strip_edges()
	if not display_name.is_empty():
		return display_name

	return NetworkManager.get_player_visible_name(peer_id)
