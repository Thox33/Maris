extends Node2D
## Handles block breaking and placing interaction for the player.
## Breaking: tracks progress, shows crack overlay, delegates to ChunkManager.
## Placing: sends intent (slot + coord) to InventoryManager for host validation.

const WORLD_INPUT_BLOCKER_GROUP := &"world_input_blocking_ui"

var _player: CharacterBody2D
var _terrain_layer: TileMapLayer
var _chunk_manager: Node
var _structure_manager: Node
var _inventory_manager: Node
var _use_authority_service: Node

## Currently selected hotbar slot (0-based, indexes into first HOTBAR_SIZE inventory slots).
var selected_hotbar_slot: int = 0

var _active_break_coord: Vector2i = Vector2i(-99999, -99999)
var _break_keepalive_timer: float = 0.0


func setup_session(
	terrain_layer: TileMapLayer,
	chunk_manager: Node,
	structure_manager: Node,
	inventory_manager: Node,
	use_authority_service: Node,
) -> void:
	_terrain_layer = terrain_layer
	_chunk_manager = chunk_manager
	_structure_manager = structure_manager
	_inventory_manager = inventory_manager
	_use_authority_service = use_authority_service


func _ready() -> void:
	_player = get_parent() as CharacterBody2D


func _process(delta: float) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if not _player.is_multiplayer_authority():
		return

	if ChatManager.is_chat_open:
		_stop_breaking()
		return

	if _is_mouse_over_world_blocking_ui():
		_stop_breaking()
		return

	if Input.is_action_pressed("break_block"):
		_handle_breaking(delta)
	else:
		_stop_breaking()

	if _has_held_cursor_item():
		if Input.is_action_just_pressed("place_block"):
			_handle_held_item_placing()
	elif Input.is_action_just_pressed("place_block"):
		_handle_placing()


func _handle_breaking(delta: float) -> void:
	if _terrain_layer == null or _use_authority_service == null:
		return

	var mouse_world := get_global_mouse_position()
	var player_pos: Vector2 = _player.global_position

	if player_pos.distance_to(mouse_world) > GameConstants.BLOCK_INTERACT_RANGE:
		_stop_breaking()
		return

	var coord := _terrain_layer.local_to_map(mouse_world)
	if not _has_breakable_target(coord):
		_stop_breaking()
		return

	_break_keepalive_timer -= delta
	var target_changed := coord != _active_break_coord
	if target_changed:
		_active_break_coord = coord
		_break_keepalive_timer = 0.0

	if target_changed or _break_keepalive_timer <= 0.0:
		_use_authority_service.request_primary_use(coord, selected_hotbar_slot)
		_break_keepalive_timer = GameConstants.PRIMARY_USE_KEEPALIVE_INTERVAL


## Sends a place-block intent to the server for the currently selected hotbar slot.
func _handle_placing() -> void:
	if _terrain_layer == null or _inventory_manager == null:
		return

	var mouse_world := get_global_mouse_position()
	var player_pos: Vector2 = _player.global_position
	if player_pos.distance_to(mouse_world) > GameConstants.BLOCK_INTERACT_RANGE:
		return

	var coord := _terrain_layer.local_to_map(mouse_world)
	if _terrain_layer.get_cell_atlas_coords(coord) != Vector2i(-1, -1):
		return

	_request_place_block(coord)


func _request_place_block(coord: Vector2i) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_inventory_manager._request_place_block(selected_hotbar_slot, coord.x, coord.y)
	else:
		_inventory_manager._request_place_block.rpc_id(1, selected_hotbar_slot, coord.x, coord.y)


func _request_place_held_block(coord: Vector2i) -> void:
	if multiplayer.multiplayer_peer == null:
		return
	if multiplayer.is_server():
		_inventory_manager._request_place_held_block(coord.x, coord.y)
	else:
		_inventory_manager._request_place_held_block.rpc_id(1, coord.x, coord.y)


func _handle_held_item_placing() -> void:
	if _terrain_layer == null or _inventory_manager == null:
		return

	var mouse_world := get_global_mouse_position()
	var player_pos: Vector2 = _player.global_position
	if player_pos.distance_to(mouse_world) > GameConstants.BLOCK_INTERACT_RANGE:
		return

	var coord := _terrain_layer.local_to_map(mouse_world)
	if _terrain_layer.get_cell_atlas_coords(coord) != Vector2i(-1, -1):
		return

	_request_place_held_block(coord)


func _has_held_cursor_item() -> bool:
	if _inventory_manager == null:
		return false
	var held: Dictionary = _inventory_manager.local_held_slot
	return held.get("item_id", ItemProperties.NONE) != ItemProperties.NONE and held.get("count", 0) > 0


func _is_mouse_over_world_blocking_ui() -> bool:
	var hovered: Node = get_viewport().gui_get_hovered_control()
	while hovered != null:
		if hovered.is_in_group(WORLD_INPUT_BLOCKER_GROUP):
			return true
		hovered = hovered.get_parent()
	return false


func _has_breakable_target(coord: Vector2i) -> bool:
	if _chunk_manager != null:
		var tile_id: int = _chunk_manager.get_top_tile_at(coord)
		if tile_id != TileProperties.EMPTY:
			var props: TileProperties = TileProperties.get_properties(tile_id)
			if props != null and props.breakable:
				return true

	if _structure_manager != null:
		var structure_data := _structure_manager.get_breakable_structure_data(coord) as Dictionary
		if not structure_data.is_empty():
			return true

	return false


func _stop_breaking() -> void:
	if _active_break_coord == Vector2i(-99999, -99999):
		return
	_active_break_coord = Vector2i(-99999, -99999)
	_break_keepalive_timer = 0.0
	if _use_authority_service != null:
		_use_authority_service.stop_primary_use()
