extends Node
## Server-authoritative structure system.
## Keeps structure occupancy separate from terrain tiles and replicates visuals to clients.

const TALL_STRUCTURE_VISUAL_SCENE := preload("res://scenes/world/tall_structure_visual.tscn")

var world_generator: Node2D
var chunk_manager: Node
var depth_sorted_node: Node2D

var _structures_by_key: Dictionary = {}
var _occupied_cells: Dictionary = {}
var _breakable_cells: Dictionary = {}
var _structure_visuals: Dictionary = {}


func setup(p_world_generator: Node2D, p_chunk_manager: Node, p_depth_sorted_node: Node2D) -> void:
	world_generator = p_world_generator
	chunk_manager = p_chunk_manager
	depth_sorted_node = p_depth_sorted_node


func load_from_save() -> void:
	_clear_runtime_state()
	if not multiplayer.is_server():
		return

	var saved_structures := SaveManager.load_structures()
	for entry in saved_structures:
		if entry is Dictionary:
			_register_structure_instance(entry, false)


func save_to_disk() -> void:
	if not multiplayer.is_server():
		return
	SaveManager.save_structures(_serialize_structures())


func sync_full_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id == multiplayer.get_unique_id():
		return
	_receive_full_state.rpc_id(peer_id, _serialize_structures())


func is_cell_occupied(coord: Vector2i) -> bool:
	return _occupied_cells.has(_cell_key(coord))


func get_breakable_structure_data(coord: Vector2i) -> Dictionary:
	var structure_key := _breakable_cells.get(_cell_key(coord), "") as String
	if structure_key.is_empty():
		return {}

	var instance_data := _structures_by_key.get(structure_key, {}) as Dictionary
	if instance_data.is_empty():
		return {}

	var definition := StructureCatalog.get_definition(String(instance_data.get("structure_id", "")))
	if definition == null:
		return {}

	return {
		"structure_id": String(instance_data.get("structure_id", "")),
		"origin": definition.get_origin_cell(instance_data),
		"hardness": definition.break_hardness,
	}


func has_structure_instance(structure_id: String, origin: Vector2i) -> bool:
	return _structures_by_key.has(_structure_key(structure_id, origin))


func get_breakable_cells_for_instance(structure_id: String, origin: Vector2i) -> Array[Vector2i]:
	if not has_structure_instance(structure_id, origin):
		return []
	var definition := StructureCatalog.get_definition(structure_id)
	if definition == null:
		return []
	return definition.get_breakable_world_cells(origin)


func can_place_structure_at(target_cell: Vector2i, structure_id: String) -> bool:
	var definition := StructureCatalog.get_definition(structure_id)
	if definition == null or chunk_manager == null:
		return false

	var origin := definition.get_origin_from_placement_cell(target_cell)

	for cell in definition.get_occupied_world_cells(origin):
		if is_cell_occupied(cell):
			return false
		if not chunk_manager.can_place_top_tile_at(cell):
			return false

	return true


func place_structure(target_cell: Vector2i, structure_id: String) -> bool:
	if not multiplayer.is_server():
		return false
	var definition := StructureCatalog.get_definition(structure_id)
	if definition == null:
		return false

	var origin := definition.get_origin_from_placement_cell(target_cell)
	if not can_place_structure_at(target_cell, structure_id):
		return false

	var data := {
		"structure_id": structure_id,
		"origin_x": origin.x,
		"origin_y": origin.y,
	}
	_register_structure_instance(data, true)
	return true


func break_structure_at(coord: Vector2i) -> bool:
	if multiplayer.is_server():
		var broken := _do_break_structure(coord)
		if broken.is_empty():
			return false
		_sync_break_structure.rpc(
			String(broken.get("structure_id", "")),
			int(broken.get("origin_x", 0)),
			int(broken.get("origin_y", 0))
		)
		var break_coord := coord
		var world_pos := Vector2(
			break_coord.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
			break_coord.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0
		)
		GameEvents.structure_broken.emit(String(broken.get("structure_id", "")), world_pos)
		return true

	_request_break_structure.rpc_id(1, coord.x, coord.y)
	return true


func break_structure_instance(structure_id: String, origin: Vector2i) -> bool:
	if not multiplayer.is_server():
		return false
	if not has_structure_instance(structure_id, origin):
		return false

	var world_pos := _get_structure_break_world_pos(structure_id, origin)
	_remove_structure_instance(structure_id, origin)
	_sync_break_structure.rpc(structure_id, origin.x, origin.y)
	GameEvents.structure_broken.emit(structure_id, world_pos)
	return true


@rpc("authority", "reliable")
func _receive_full_state(serialized_structures: Array) -> void:
	_clear_runtime_state()
	for entry in serialized_structures:
		if entry is Dictionary:
			_register_structure_instance(entry, false)


@rpc("authority", "reliable")
func _sync_place_structure(data: Dictionary) -> void:
	_register_structure_instance(data, false)


@rpc("any_peer", "reliable")
func _request_break_structure(tx: int, ty: int) -> void:
	if not multiplayer.is_server():
		return

	var coord := Vector2i(tx, ty)
	var broken := _do_break_structure(coord)
	if broken.is_empty():
		return

	_sync_break_structure.rpc(
		String(broken.get("structure_id", "")),
		int(broken.get("origin_x", 0)),
		int(broken.get("origin_y", 0))
	)
	var world_pos := Vector2(
		coord.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
		coord.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0
	)
	GameEvents.structure_broken.emit(String(broken.get("structure_id", "")), world_pos)


@rpc("authority", "reliable")
func _sync_break_structure(structure_id: String, origin_x: int, origin_y: int) -> void:
	var origin := Vector2i(origin_x, origin_y)
	var world_pos := _get_structure_break_world_pos(structure_id, origin)
	_remove_structure_instance(structure_id, origin)
	GameEvents.structure_broken.emit(structure_id, world_pos)


func _register_structure_instance(data: Dictionary, broadcast_to_clients: bool) -> void:
	var structure_id := String(data.get("structure_id", ""))
	var definition := StructureCatalog.get_definition(structure_id)
	if definition == null:
		return

	var origin := definition.get_origin_cell(data)
	var key := _structure_key(structure_id, origin)
	if _structures_by_key.has(key):
		return

	var instance_data := {
		"structure_id": structure_id,
		"origin_x": origin.x,
		"origin_y": origin.y,
	}
	_structures_by_key[key] = instance_data
	for cell in definition.get_occupied_world_cells(origin):
		_occupied_cells[_cell_key(cell)] = key
	for cell in definition.get_breakable_world_cells(origin):
		_breakable_cells[_cell_key(cell)] = key

	_spawn_structure_visual(key, definition, origin)

	if broadcast_to_clients:
		_sync_place_structure.rpc(instance_data)


func _spawn_structure_visual(
	key: String, definition: StructureDefinition, origin: Vector2i
) -> void:
	var visual := TALL_STRUCTURE_VISUAL_SCENE.instantiate() as TallStructureVisual
	visual.name = "Structure_%s_%s_%s" % [definition.id, origin.x, origin.y]
	visual.atlas_texture = load(definition.atlas_texture_path)
	visual.position = definition.get_world_position(origin)
	visual.configure_parts(
		definition.build_visual_parts(),
		true,
		definition.build_collision_rects()
	)
	depth_sorted_node.add_child(visual)
	_structure_visuals[key] = visual


func _serialize_structures() -> Array[Dictionary]:
	var serialized: Array[Dictionary] = []
	for key in _structures_by_key.keys():
		serialized.append((_structures_by_key[key] as Dictionary).duplicate(true))
	return serialized


func _clear_runtime_state() -> void:
	for visual in _structure_visuals.values():
		if visual is Node:
			(visual as Node).queue_free()
	_structure_visuals.clear()
	_structures_by_key.clear()
	_occupied_cells.clear()
	_breakable_cells.clear()


func _structure_key(structure_id: String, origin: Vector2i) -> String:
	return "%s:%s:%s" % [structure_id, origin.x, origin.y]


func _cell_key(coord: Vector2i) -> String:
	return "%s:%s" % [coord.x, coord.y]


func _do_break_structure(coord: Vector2i) -> Dictionary:
	var break_data := get_breakable_structure_data(coord)
	if break_data.is_empty():
		return {}

	var structure_id := String(break_data.get("structure_id", ""))
	var origin := break_data.get("origin", Vector2i.ZERO) as Vector2i
	_remove_structure_instance(structure_id, origin)
	return {
		"structure_id": structure_id,
		"origin_x": origin.x,
		"origin_y": origin.y,
	}


func _remove_structure_instance(structure_id: String, origin: Vector2i) -> void:
	var key := _structure_key(structure_id, origin)
	var instance_data := _structures_by_key.get(key, {}) as Dictionary
	if instance_data.is_empty():
		return

	var definition := StructureCatalog.get_definition(structure_id)
	if definition == null:
		return

	for cell in definition.get_occupied_world_cells(origin):
		_occupied_cells.erase(_cell_key(cell))
	for cell in definition.get_breakable_world_cells(origin):
		_breakable_cells.erase(_cell_key(cell))

	_structures_by_key.erase(key)

	var visual := _structure_visuals.get(key) as Node
	if visual != null:
		_structure_visuals.erase(key)
		visual.queue_free()


func _get_structure_break_world_pos(structure_id: String, origin: Vector2i) -> Vector2:
	var definition := StructureCatalog.get_definition(structure_id)
	if definition == null:
		return Vector2(
			origin.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
			origin.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0
		)
	var breakable_cells := definition.get_breakable_world_cells(origin)
	if breakable_cells.is_empty():
		return Vector2(
			origin.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
			origin.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0
		)

	var sum := Vector2.ZERO
	for cell in breakable_cells:
		sum += Vector2(
			cell.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
			cell.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0
		)
	return sum / float(breakable_cells.size())
