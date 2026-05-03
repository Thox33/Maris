class_name WorldObjectManager
extends Node

signal breakable_world_visual_created(target_key: String, visual: Node)
signal breakable_world_visual_detached(target_key: String, visual: Node)

const TALL_STRUCTURE_VISUAL_SCENE := preload("res://scenes/world/tall_structure_visual.tscn")

var _world_object_catalog = preload("res://scripts/world/world_object_catalog.gd").new()
var _world_prop_catalog = preload("res://scripts/world/world_prop_catalog.gd").new()

var world_generator: Node2D
var chunk_manager: Node
var depth_sorted_node: Node2D

var _world_objects_by_key: Dictionary = {}
var _world_object_visuals: Dictionary = {}
var _occupied_cells: Dictionary = {}
var _hit_cells: Dictionary = {}
var _breakable_cells: Dictionary = {}
var _world_object_keys_by_chunk: Dictionary = {}
var _world_object_loaded_chunk_refs_by_key: Dictionary = {}
var _coverage_origin_bounds: Dictionary = {}


func setup(p_world_generator: Node2D, p_chunk_manager: Node, p_depth_sorted_node: Node2D) -> void:
	world_generator = p_world_generator
	chunk_manager = p_chunk_manager
	depth_sorted_node = p_depth_sorted_node


func load_from_save() -> void:
	_clear_runtime_state()
	if not multiplayer.is_server():
		return
	_migrate_legacy_structure_save()


func apply_saved_world_object_modifications(chunk: ChunkData, saved: Dictionary) -> void:
	chunk.world_object_additions = _duplicate_nested_dict(
		saved.get("world_object_additions", {})
	)
	chunk.world_object_removals = _duplicate_nested_dict(
		saved.get("world_object_removals", {})
	)

	var legacy_prop_mods: Variant = saved.get("prop_mods", saved.get("props", {}))
	if legacy_prop_mods is Dictionary and not (legacy_prop_mods as Dictionary).is_empty():
		_migrate_legacy_prop_modifications(chunk, legacy_prop_mods as Dictionary)


func apply_chunk_objects(chunk: ChunkData) -> void:
	clear_chunk_objects(chunk.chunk_coord)
	var covering_objects := _prepare_chunk_covering_world_objects(chunk)
	for object_key_variant in covering_objects.keys():
		var object_data := covering_objects[object_key_variant] as Dictionary
		if object_data.is_empty():
			continue
		_register_world_object_instance(chunk.chunk_coord, object_data)


func clear_chunk_objects(chunk_coord: Vector2i) -> void:
	var chunk_key := _chunk_key(chunk_coord)
	var object_keys := (_world_object_keys_by_chunk.get(chunk_key, {}) as Dictionary).duplicate(true)
	for object_key_variant in object_keys.keys():
		_release_world_object_chunk_reference(String(object_key_variant), chunk_coord, false)


func is_cell_occupied(coord: Vector2i) -> bool:
	return _occupied_cells.has(_cell_key(coord))


func get_move_speed_factor_at(coord: Vector2i) -> float:
	var object_data := resolve_world_object_at(coord)
	if object_data.is_empty():
		return 1.0
	return float(object_data.get("move_speed_factor", 1.0))


func resolve_world_object_at(coord: Vector2i) -> Dictionary:
	return _build_resolved_world_object_data(_resolve_object_key_at(_hit_cells, coord))


func resolve_breakable_world_object_at(coord: Vector2i) -> Dictionary:
	return _build_resolved_world_object_data(_resolve_object_key_at(_breakable_cells, coord))


func can_place_world_object_at(target_cell: Vector2i, object_id: String) -> bool:
	var definition = _get_definition(object_id)
	if definition == null or chunk_manager == null:
		return false

	var origin: Vector2i = definition.get_origin_from_placement_cell(target_cell)
	for occupied_cell in definition.get_occupied_world_cells(origin):
		if is_cell_occupied(occupied_cell):
			return false
		if not chunk_manager.can_place_top_tile_at(occupied_cell):
			return false

		var ground_id := int(chunk_manager.get_ground_tile_at(occupied_cell))
		var ground_props := GroundTileProperties.get_properties(ground_id)
		if ground_props == null or not ground_props.is_solid:
			return false
		if not definition.is_ground_allowed(String(ground_props.name)):
			return false

	return true


func place_world_object(target_cell: Vector2i, object_id: String) -> bool:
	if not multiplayer.is_server():
		return false

	var placed_object_id := String(_world_object_catalog.call("resolve_placement_object_id", object_id))
	var definition = _get_definition(placed_object_id)
	if definition == null:
		return false
	if not can_place_world_object_at(target_cell, placed_object_id):
		return false

	var origin: Vector2i = definition.get_origin_from_placement_cell(target_cell)
	var chunk := _get_loaded_chunk(_cell_to_chunk(origin))
	if chunk == null:
		return false

	var local_origin := _world_to_local(origin, chunk.chunk_coord)
	chunk.add_world_object_addition(local_origin, placed_object_id)
	_add_world_object_to_loaded_chunk_coverages(placed_object_id, origin)

	if multiplayer.multiplayer_peer != null:
		_sync_place_world_object.rpc(placed_object_id, origin.x, origin.y)
	_emit_world_object_placed(placed_object_id, origin)
	return true


func break_world_object_instance(object_id: String, origin: Vector2i) -> bool:
	if not multiplayer.is_server():
		return false
	if not has_world_object_instance(object_id, origin):
		return false

	var world_pos := _get_break_world_pos(object_id, origin)
	if not _remove_world_object_from_chunk(object_id, origin):
		return false

	_remove_world_object_from_loaded_chunk_coverages(object_id, origin)
	_remove_world_object_instance(_world_object_key(object_id, origin), true)
	if multiplayer.multiplayer_peer != null:
		_sync_break_world_object.rpc(object_id, origin.x, origin.y)
	_emit_world_object_broken(object_id, origin, world_pos)
	return true


func has_world_object_instance(object_id: String, origin: Vector2i) -> bool:
	return _world_objects_by_key.has(_world_object_key(object_id, origin))


func get_world_object_visual(object_id: String, origin: Vector2i) -> Node:
	var visual := _world_object_visuals.get(_world_object_key(object_id, origin)) as Node
	if visual == null or not is_instance_valid(visual):
		return null
	return visual


func get_structure_visual(structure_id: String, origin: Vector2i) -> Node:
	return get_world_object_visual(structure_id, origin)


@rpc("authority", "reliable")
func _sync_place_world_object(object_id: String, origin_x: int, origin_y: int) -> void:
	var origin := Vector2i(origin_x, origin_y)
	_add_world_object_to_loaded_chunk_coverages(object_id, origin)
	_emit_world_object_placed(object_id, origin)


@rpc("authority", "reliable")
func _sync_break_world_object(object_id: String, origin_x: int, origin_y: int) -> void:
	var origin := Vector2i(origin_x, origin_y)
	var world_pos := _get_break_world_pos(object_id, origin)
	_remove_world_object_from_chunk(object_id, origin)
	_remove_world_object_from_loaded_chunk_coverages(object_id, origin)
	_remove_world_object_instance(_world_object_key(object_id, origin), true)
	_emit_world_object_broken(object_id, origin, world_pos)


func _register_world_object_instance(chunk_coord: Vector2i, object_data: Dictionary) -> void:
	var object_id := String(object_data.get("object_id", ""))
	var definition = _get_definition(object_id)
	if definition == null:
		return

	var origin := Vector2i(int(object_data.get("origin_x", 0)), int(object_data.get("origin_y", 0)))
	var object_key := _world_object_key(object_id, origin)
	if _world_objects_by_key.has(object_key):
		_add_loaded_chunk_reference(object_key, chunk_coord)
		return

	var covered_chunks := _get_covered_chunks(definition, origin)
	var covered_chunk_keys: Dictionary = {}
	for covered_chunk in covered_chunks:
		covered_chunk_keys[_chunk_key(covered_chunk)] = true

	var runtime_data := {
		"object_id": object_id,
		"origin_x": origin.x,
		"origin_y": origin.y,
		"covered_chunks": covered_chunks,
		"covered_chunk_keys": covered_chunk_keys,
	}
	_world_objects_by_key[object_key] = runtime_data

	for occupied_cell in definition.get_occupied_world_cells(origin):
		_occupied_cells[_cell_key(occupied_cell)] = object_key
	for hit_cell in definition.get_hit_world_cells(origin):
		_append_cell_object_key(_hit_cells, hit_cell, object_key)
	for breakable_cell in definition.get_breakable_world_cells(origin):
		_append_cell_object_key(_breakable_cells, breakable_cell, object_key)

	_spawn_world_object_visual(object_key, definition, origin)
	_add_loaded_chunk_reference(object_key, chunk_coord)


func _remove_world_object_instance(object_key: String, detach_visual_for_break: bool) -> void:
	var runtime_data := _world_objects_by_key.get(object_key, {}) as Dictionary
	if runtime_data.is_empty():
		return

	var object_id := String(runtime_data.get("object_id", ""))
	var origin := Vector2i(int(runtime_data.get("origin_x", 0)), int(runtime_data.get("origin_y", 0)))
	var definition = _get_definition(object_id)
	if definition != null:
		for occupied_cell in definition.get_occupied_world_cells(origin):
			_occupied_cells.erase(_cell_key(occupied_cell))
		for hit_cell in definition.get_hit_world_cells(origin):
			_remove_cell_object_key(_hit_cells, hit_cell, object_key)
		for breakable_cell in definition.get_breakable_world_cells(origin):
			_remove_cell_object_key(_breakable_cells, breakable_cell, object_key)

	var loaded_chunk_refs := _world_object_loaded_chunk_refs_by_key.get(object_key, {}) as Dictionary
	for chunk_key_variant in loaded_chunk_refs.keys():
		_remove_object_key_from_chunk(String(chunk_key_variant), object_key)
	_world_object_loaded_chunk_refs_by_key.erase(object_key)

	_world_objects_by_key.erase(object_key)

	var visual := _world_object_visuals.get(object_key) as Node
	if visual == null:
		return
	_world_object_visuals.erase(object_key)

	if detach_visual_for_break:
		breakable_world_visual_detached.emit(
			_world_object_target_key(object_id, origin),
			visual
		)
	else:
		visual.queue_free()


func _spawn_world_object_visual(object_key: String, definition, origin: Vector2i) -> void:
	if depth_sorted_node == null:
		return

	var visual := TALL_STRUCTURE_VISUAL_SCENE.instantiate()
	visual.name = "WorldObject_%s_%s_%s" % [definition.id, origin.x, origin.y]
	visual.atlas_texture = load(String(definition.atlas_texture_path))
	visual.position = definition.get_world_position(origin)

	var collision_rects: Array[Dictionary] = definition.build_collision_rects()
	visual.configure_parts(
		definition.build_visual_parts(),
		not collision_rects.is_empty(),
		collision_rects,
		definition.anchor_offset_px,
		{
			"sway_enabled": bool(definition.sway_enabled),
			"sway_amount": float(definition.sway_amount),
			"sway_speed": float(definition.sway_speed),
			"rigid_base_px": float(definition.rigid_base_px),
			"phase_seed": float((absi(origin.x * 73 + origin.y * 137) % 1024)) / 1024.0 * TAU,
		}
	)

	depth_sorted_node.add_child(visual)
	_world_object_visuals[object_key] = visual
	breakable_world_visual_created.emit(
		_world_object_target_key(definition.id, origin),
		visual
	)


func _build_resolved_world_object_data(object_key: String) -> Dictionary:
	if object_key.is_empty():
		return {}

	var runtime_data := _world_objects_by_key.get(object_key, {}) as Dictionary
	if runtime_data.is_empty():
		return {}

	var object_id := String(runtime_data.get("object_id", ""))
	var definition = _get_definition(object_id)
	if definition == null:
		return {}

	var origin := Vector2i(int(runtime_data.get("origin_x", 0)), int(runtime_data.get("origin_y", 0)))
	return {
		"object_id": object_id,
		"origin": origin,
		"kind": String(definition.kind),
		"durability": float(definition.break_hardness),
		"move_speed_factor": float(definition.move_speed_factor),
	}


func _remove_world_object_from_chunk(object_id: String, origin: Vector2i) -> bool:
	var chunk_coord := _cell_to_chunk(origin)
	var chunk := _get_loaded_chunk(chunk_coord)
	var chunk_was_loaded := chunk != null
	if chunk == null and multiplayer.is_server():
		chunk = _load_chunk_for_persistence(chunk_coord)
	if chunk == null:
		return false

	var local_origin := _world_to_local(origin, chunk.chunk_coord)
	var object_key := ChunkData.build_world_object_key(object_id, local_origin)
	var removed := chunk.remove_world_object(object_key)
	if removed and not chunk_was_loaded and multiplayer.is_server():
		SaveManager.save_chunk(chunk_coord, chunk)
	return removed


func _get_break_world_pos(object_id: String, origin: Vector2i) -> Vector2:
	var definition = _get_definition(object_id)
	if definition == null:
		return Vector2(
			origin.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
			origin.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0
		)
	return definition.get_break_world_position(origin)


func _emit_world_object_placed(object_id: String, origin: Vector2i) -> void:
	GameEvents.world_object_placed.emit(object_id, origin)

	var definition = _get_definition(object_id)
	if definition == null:
		return
	if int(definition.legacy_prop_id) >= 0:
		GameEvents.prop_placed.emit(origin, int(definition.legacy_prop_id))


func _emit_world_object_broken(object_id: String, origin: Vector2i, world_pos: Vector2) -> void:
	GameEvents.world_object_broken.emit(object_id, origin, world_pos)

	var definition = _get_definition(object_id)
	if definition == null:
		return
	if int(definition.legacy_prop_id) >= 0:
		GameEvents.prop_broken.emit(origin, int(definition.legacy_prop_id))
	if not String(definition.legacy_structure_id).is_empty():
		GameEvents.structure_broken.emit(String(definition.legacy_structure_id), world_pos)


func _migrate_legacy_prop_modifications(chunk: ChunkData, legacy_prop_mods: Dictionary) -> void:
	for key_variant in legacy_prop_mods.keys():
		var key := int(key_variant)
		var prop_id := int(legacy_prop_mods.get(key_variant, legacy_prop_mods.get(key, -1)))
		var local_origin := Vector2i(
			key % GameConstants.CHUNK_SIZE,
			floori(float(key) / float(GameConstants.CHUNK_SIZE))
		)
		var generated_key := _find_generated_world_object_key_at(chunk, local_origin)

		if prop_id == int(_world_prop_catalog.get("EMPTY")):
			if not generated_key.is_empty():
				chunk.world_object_removals[generated_key] = true
				chunk.world_object_additions.erase(generated_key)
			continue

		var definition = _world_object_catalog.call("get_definition_by_prop_id", prop_id)
		if definition == null:
			continue

		var object_key := ChunkData.build_world_object_key(String(definition.id), local_origin)
		var object_data := {
			"object_id": String(definition.id),
			"origin_x": local_origin.x,
			"origin_y": local_origin.y,
		}

		if not generated_key.is_empty() and generated_key != object_key:
			chunk.world_object_removals[generated_key] = true
		else:
			chunk.world_object_removals.erase(object_key)

		if generated_key == object_key:
			chunk.world_object_additions.erase(object_key)
		else:
			chunk.world_object_additions[object_key] = object_data


func _find_generated_world_object_key_at(chunk: ChunkData, local_origin: Vector2i) -> String:
	for object_key_variant in chunk.base_world_objects.keys():
		var object_data := chunk.base_world_objects[object_key_variant] as Dictionary
		if object_data.is_empty():
			continue
		if ChunkData.local_origin_from_data(object_data) == local_origin:
			return String(object_key_variant)
	return ""


func _migrate_legacy_structure_save() -> void:
	var saved_structures := SaveManager.load_structures()
	if saved_structures.is_empty():
		return

	for entry in saved_structures:
		if not (entry is Dictionary):
			continue
		var structure_data := entry as Dictionary
		var structure_id := String(structure_data.get("structure_id", ""))
		var definition = _world_object_catalog.call("get_definition_by_structure_id", structure_id)
		if definition == null:
			continue

		var origin := Vector2i(
			int(structure_data.get("origin_x", 0)),
			int(structure_data.get("origin_y", 0))
		)
		var chunk_coord := _cell_to_chunk(origin)
		var local_origin := _world_to_local(origin, chunk_coord)
		var chunk_save := SaveManager.load_chunk_modifications(chunk_coord).duplicate(true)
		var additions := _duplicate_nested_dict(chunk_save.get("world_object_additions", {}))
		var removals := _duplicate_nested_dict(chunk_save.get("world_object_removals", {}))
		var object_key := ChunkData.build_world_object_key(String(definition.id), local_origin)
		additions[object_key] = {
			"object_id": String(definition.id),
			"origin_x": local_origin.x,
			"origin_y": local_origin.y,
		}
		removals.erase(object_key)
		chunk_save["world_object_additions"] = additions
		chunk_save["world_object_removals"] = removals
		_write_chunk_save_dict(chunk_coord, chunk_save)

	SaveManager.delete_legacy_structures_save()


func _write_chunk_save_dict(coord: Vector2i, data: Dictionary) -> void:
	var world_dir := GameConstants.SAVE_DIR + SaveManager.get_world_name() + "/"
	var path := "%schunks/chunk_%d_%d.dat" % [world_dir, coord.x, coord.y]
	var tmp_path := path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error(
			"[WorldObjectManager] Failed to migrate chunk save %s: %s"
			% [tmp_path, error_string(FileAccess.get_open_error())]
		)
		return
	file.store_buffer(var_to_bytes(data))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp_path, path)


func _get_definition(object_id: String):
	return _world_object_catalog.call("get_definition", object_id)


func _prepare_chunk_covering_world_objects(chunk: ChunkData) -> Dictionary:
	if multiplayer.is_server():
		var covering_objects := _build_covering_world_objects_for_chunk(chunk.chunk_coord)
		chunk.set_covering_world_objects(covering_objects)
		return covering_objects
	return chunk.get_covering_world_objects()


func _build_covering_world_objects_for_chunk(chunk_coord: Vector2i) -> Dictionary:
	var covering_objects: Dictionary = {}
	for origin_chunk_coord in _get_candidate_origin_chunks_for_chunk(chunk_coord):
		var source_chunk := _get_loaded_chunk(origin_chunk_coord)
		if source_chunk == null:
			source_chunk = _load_chunk_for_persistence(origin_chunk_coord)
		if source_chunk == null:
			continue

		var effective_objects := source_chunk.get_effective_world_objects()
		for object_key_variant in effective_objects.keys():
			var local_object_data := effective_objects[object_key_variant] as Dictionary
			if local_object_data.is_empty():
				continue

			var object_id := String(local_object_data.get("object_id", ""))
			if object_id.is_empty():
				continue

			var local_origin := ChunkData.local_origin_from_data(local_object_data)
			var origin := _local_to_world(local_origin, origin_chunk_coord)
			if not _world_object_covers_chunk(object_id, origin, chunk_coord):
				continue

			var object_key := _world_object_key(object_id, origin)
			covering_objects[object_key] = _build_world_object_coverage_data(object_id, origin)

	return covering_objects


func _add_world_object_to_loaded_chunk_coverages(object_id: String, origin: Vector2i) -> void:
	var definition = _get_definition(object_id)
	if definition == null:
		return

	var object_key := _world_object_key(object_id, origin)
	var object_data := _build_world_object_coverage_data(object_id, origin)
	for covered_chunk in _get_covered_chunks(definition, origin):
		var chunk := _get_loaded_chunk(covered_chunk)
		if chunk == null:
			continue
		chunk.upsert_covering_world_object(object_key, object_data)
		_register_world_object_instance(covered_chunk, object_data)


func _remove_world_object_from_loaded_chunk_coverages(object_id: String, origin: Vector2i) -> void:
	var definition = _get_definition(object_id)
	if definition == null:
		return

	var object_key := _world_object_key(object_id, origin)
	for covered_chunk in _get_covered_chunks(definition, origin):
		var chunk := _get_loaded_chunk(covered_chunk)
		if chunk == null:
			continue
		chunk.erase_covering_world_object(object_key)


func _build_world_object_coverage_data(object_id: String, origin: Vector2i) -> Dictionary:
	return {
		"object_id": object_id,
		"origin_x": origin.x,
		"origin_y": origin.y,
	}


func _release_world_object_chunk_reference(
	object_key: String,
	chunk_coord: Vector2i,
	detach_visual_for_break: bool
) -> void:
	_remove_loaded_chunk_reference(object_key, chunk_coord)
	var loaded_chunk_refs := _world_object_loaded_chunk_refs_by_key.get(object_key, {}) as Dictionary
	if loaded_chunk_refs.is_empty():
		_remove_world_object_instance(object_key, detach_visual_for_break)


func _add_loaded_chunk_reference(object_key: String, chunk_coord: Vector2i) -> void:
	var chunk_key := _chunk_key(chunk_coord)
	var loaded_chunk_refs := _world_object_loaded_chunk_refs_by_key.get(object_key, {}) as Dictionary
	if loaded_chunk_refs.has(chunk_key):
		return
	loaded_chunk_refs[chunk_key] = true
	_world_object_loaded_chunk_refs_by_key[object_key] = loaded_chunk_refs

	var chunk_object_keys := _world_object_keys_by_chunk.get(chunk_key, {}) as Dictionary
	chunk_object_keys[object_key] = true
	_world_object_keys_by_chunk[chunk_key] = chunk_object_keys


func _remove_loaded_chunk_reference(object_key: String, chunk_coord: Vector2i) -> void:
	var chunk_key := _chunk_key(chunk_coord)
	var loaded_chunk_refs := _world_object_loaded_chunk_refs_by_key.get(object_key, {}) as Dictionary
	if loaded_chunk_refs.is_empty() or not loaded_chunk_refs.has(chunk_key):
		return
	loaded_chunk_refs.erase(chunk_key)
	if loaded_chunk_refs.is_empty():
		_world_object_loaded_chunk_refs_by_key.erase(object_key)
	else:
		_world_object_loaded_chunk_refs_by_key[object_key] = loaded_chunk_refs
	_remove_object_key_from_chunk(chunk_key, object_key)


func _remove_object_key_from_chunk(chunk_key: String, object_key: String) -> void:
	var chunk_object_keys := _world_object_keys_by_chunk.get(chunk_key, {}) as Dictionary
	if chunk_object_keys.is_empty():
		return
	chunk_object_keys.erase(object_key)
	if chunk_object_keys.is_empty():
		_world_object_keys_by_chunk.erase(chunk_key)
	else:
		_world_object_keys_by_chunk[chunk_key] = chunk_object_keys


func _get_covered_chunks(definition, origin: Vector2i) -> Array[Vector2i]:
	var covered_chunk_map: Dictionary = {}
	var relevant_cells: Array[Vector2i] = []
	relevant_cells.append_array(definition.get_hit_world_cells(origin))
	relevant_cells.append_array(definition.get_occupied_world_cells(origin))
	relevant_cells.append_array(definition.get_breakable_world_cells(origin))
	relevant_cells.append_array(definition.get_collision_world_cells(origin))

	if relevant_cells.is_empty():
		relevant_cells.append(origin)

	for world_cell in relevant_cells:
		var chunk_coord := _cell_to_chunk(world_cell)
		covered_chunk_map[_chunk_key(chunk_coord)] = chunk_coord

	var covered_chunks: Array[Vector2i] = []
	for chunk_coord_variant in covered_chunk_map.values():
		covered_chunks.append(chunk_coord_variant as Vector2i)
	return covered_chunks


func _world_object_covers_chunk(object_id: String, origin: Vector2i, chunk_coord: Vector2i) -> bool:
	var definition = _get_definition(object_id)
	if definition == null:
		return false
	for covered_chunk in _get_covered_chunks(definition, origin):
		if covered_chunk == chunk_coord:
			return true
	return false


func _get_candidate_origin_chunks_for_chunk(chunk_coord: Vector2i) -> Array[Vector2i]:
	var bounds := _get_coverage_origin_bounds()
	var min_world_x := chunk_coord.x * GameConstants.CHUNK_SIZE - int(bounds.get("max_x", 0))
	var max_world_x := (
		chunk_coord.x * GameConstants.CHUNK_SIZE
		+ GameConstants.CHUNK_SIZE
		- 1
		- int(bounds.get("min_x", 0))
	)
	var min_world_y := chunk_coord.y * GameConstants.CHUNK_SIZE - int(bounds.get("max_y", 0))
	var max_world_y := (
		chunk_coord.y * GameConstants.CHUNK_SIZE
		+ GameConstants.CHUNK_SIZE
		- 1
		- int(bounds.get("min_y", 0))
	)

	var min_chunk := _cell_to_chunk(Vector2i(min_world_x, min_world_y))
	var max_chunk := _cell_to_chunk(Vector2i(max_world_x, max_world_y))
	var result: Array[Vector2i] = []
	for y in range(min_chunk.y, max_chunk.y + 1):
		for x in range(min_chunk.x, max_chunk.x + 1):
			result.append(Vector2i(x, y))
	return result


func _get_coverage_origin_bounds() -> Dictionary:
	if not _coverage_origin_bounds.is_empty():
		return _coverage_origin_bounds

	var min_x := 0
	var max_x := 0
	var min_y := 0
	var max_y := 0
	for definition_variant in _world_object_catalog.registry.values():
		var definition = definition_variant
		if definition == null:
			continue

		var relevant_cells: Array[Vector2i] = []
		relevant_cells.append_array(definition.hit_cells)
		relevant_cells.append_array(definition.occupied_cells)
		relevant_cells.append_array(definition.breakable_cells)
		relevant_cells.append_array(definition.collision_cells)
		if relevant_cells.is_empty():
			relevant_cells.append(Vector2i.ZERO)

		for offset in relevant_cells:
			min_x = mini(min_x, offset.x)
			max_x = maxi(max_x, offset.x)
			min_y = mini(min_y, offset.y)
			max_y = maxi(max_y, offset.y)

	_coverage_origin_bounds = {
		"min_x": min_x,
		"max_x": max_x,
		"min_y": min_y,
		"max_y": max_y,
	}
	return _coverage_origin_bounds


func _get_loaded_chunk(chunk_coord: Vector2i) -> ChunkData:
	if chunk_manager == null:
		return null
	var loaded_chunks: Dictionary = chunk_manager.loaded_chunks
	return loaded_chunks.get(chunk_coord) as ChunkData


func _load_chunk_for_persistence(chunk_coord: Vector2i) -> ChunkData:
	if chunk_manager == null or not chunk_manager.has_method("_generate_and_restore"):
		return null
	return chunk_manager._generate_and_restore(chunk_coord) as ChunkData


func _append_cell_object_key(map: Dictionary, coord: Vector2i, object_key: String) -> void:
	var cell_key := _cell_key(coord)
	var object_keys := _get_cell_object_keys(map, coord)
	if object_key in object_keys:
		return
	object_keys.append(object_key)
	map[cell_key] = object_keys


func _remove_cell_object_key(map: Dictionary, coord: Vector2i, object_key: String) -> void:
	var cell_key := _cell_key(coord)
	var object_keys := _get_cell_object_keys(map, coord)
	if object_keys.is_empty():
		return
	object_keys.erase(object_key)
	if object_keys.is_empty():
		map.erase(cell_key)
	else:
		map[cell_key] = object_keys


func _resolve_object_key_at(map: Dictionary, coord: Vector2i) -> String:
	var object_keys := _get_cell_object_keys(map, coord)
	if object_keys.is_empty():
		return ""

	for index in range(object_keys.size() - 1, -1, -1):
		var object_key := object_keys[index]
		if _object_occupies_cell(object_key, coord):
			return object_key

	return object_keys[object_keys.size() - 1]


func _get_cell_object_keys(map: Dictionary, coord: Vector2i) -> Array[String]:
	var value: Variant = map.get(_cell_key(coord), [])
	var result: Array[String] = []
	if value is Array:
		for object_key_variant in value:
			result.append(String(object_key_variant))
	elif value is String and not String(value).is_empty():
		result.append(String(value))
	return result


func _object_occupies_cell(object_key: String, coord: Vector2i) -> bool:
	var runtime_data := _world_objects_by_key.get(object_key, {}) as Dictionary
	if runtime_data.is_empty():
		return false

	var definition = _get_definition(String(runtime_data.get("object_id", "")))
	if definition == null:
		return false

	var origin := Vector2i(int(runtime_data.get("origin_x", 0)), int(runtime_data.get("origin_y", 0)))
	return coord in definition.get_occupied_world_cells(origin)


func _duplicate_nested_dict(source: Variant) -> Dictionary:
	if not (source is Dictionary):
		return {}
	return (source as Dictionary).duplicate(true)


func _clear_runtime_state() -> void:
	for visual_variant in _world_object_visuals.values():
		var visual := visual_variant as Node
		if visual != null and is_instance_valid(visual):
			visual.queue_free()
	_world_object_visuals.clear()
	_world_objects_by_key.clear()
	_occupied_cells.clear()
	_hit_cells.clear()
	_breakable_cells.clear()
	_world_object_keys_by_chunk.clear()
	_world_object_loaded_chunk_refs_by_key.clear()


func _world_object_key(object_id: String, origin: Vector2i) -> String:
	return "%s:%s:%s" % [object_id, origin.x, origin.y]


func _world_object_target_key(object_id: String, origin: Vector2i) -> String:
	return "world_object:%s:%s:%s" % [object_id, origin.x, origin.y]


func _chunk_key(chunk_coord: Vector2i) -> String:
	return "%s:%s" % [chunk_coord.x, chunk_coord.y]


func _cell_key(coord: Vector2i) -> String:
	return "%s:%s" % [coord.x, coord.y]


func _cell_to_chunk(coord: Vector2i) -> Vector2i:
	return Vector2i(
		floori(float(coord.x) / GameConstants.CHUNK_SIZE),
		floori(float(coord.y) / GameConstants.CHUNK_SIZE)
	)


func _world_to_local(coord: Vector2i, chunk_coord: Vector2i) -> Vector2i:
	return Vector2i(
		coord.x - chunk_coord.x * GameConstants.CHUNK_SIZE,
		coord.y - chunk_coord.y * GameConstants.CHUNK_SIZE
	)


func _local_to_world(local_coord: Vector2i, chunk_coord: Vector2i) -> Vector2i:
	return Vector2i(
		chunk_coord.x * GameConstants.CHUNK_SIZE + local_coord.x,
		chunk_coord.y * GameConstants.CHUNK_SIZE + local_coord.y
	)
