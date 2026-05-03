extends Node

signal breakable_world_visual_created(target_key: String, visual: Node)

var _world_object_catalog = preload("res://scripts/world/world_object_catalog.gd").new()
var _world_prop_catalog = preload("res://scripts/world/world_prop_catalog.gd").new()
const TALL_STRUCTURE_VISUAL_SCENE := preload("res://scenes/world/tall_structure_visual.tscn")

const DEBUG_LOG: bool = false

var world_generator: Node2D
var world_object_manager: Node
var ground_layer: TileMapLayer
var ground_collision_layer: TileMapLayer
var liquid_layer: TileMapLayer
var terrain_layer: TileMapLayer
var base_visual_layer: TileMapLayer
var decor_layer: TileMapLayer
var tall_structure_visuals_node: Node2D
var _tall_structure_visuals: Dictionary = {}
var loaded_chunks: Dictionary = {}
var _update_timer: float = 0.0
var _players_node: Node
var _load_queue: Array[Vector2i] = []
var _unload_queue: Array[Vector2i] = []


func setup(
	p_world_generator: Node2D,
	p_world_object_manager: Node,
	p_ground_layer: TileMapLayer,
	p_ground_collision_layer: TileMapLayer,
	p_liquid_layer: TileMapLayer,
	p_terrain_layer: TileMapLayer,
	p_base_visual_layer: TileMapLayer,
	p_decor_layer: TileMapLayer,
	p_tall_structure_visuals_node: Node2D,
	p_players_node: Node,
) -> void:
	world_generator = p_world_generator
	world_object_manager = p_world_object_manager
	ground_layer = p_ground_layer
	ground_collision_layer = p_ground_collision_layer
	liquid_layer = p_liquid_layer
	terrain_layer = p_terrain_layer
	base_visual_layer = p_base_visual_layer
	decor_layer = p_decor_layer
	tall_structure_visuals_node = p_tall_structure_visuals_node
	_players_node = p_players_node


func load_chunks_around(world_pos: Vector2) -> void:
	var center := _world_to_chunk(world_pos)
	var r := GameConstants.CHUNK_LOAD_RADIUS
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var coord := Vector2i(center.x + dx, center.y + dy)
			if loaded_chunks.has(coord):
				continue
			if multiplayer.is_server():
				var chunk: ChunkData = _generate_and_restore(coord)
				_apply_chunk(chunk)
			else:
				_request_chunk.rpc_id(1, coord.x, coord.y)
				loaded_chunks[coord] = null
	if DEBUG_LOG:
		print("[ChunkManager] Initial load around %s - total: %d" % [center, loaded_chunks.size()])


func _process(delta: float) -> void:
	_process_load_queue()
	_process_unload_queue()

	_update_timer += delta
	if _update_timer < GameConstants.CHUNK_UPDATE_INTERVAL:
		return
	_update_timer = 0.0

	if _players_node == null:
		return

	var needed_chunks: Dictionary = {}
	_collect_needed_chunks(needed_chunks)
	_enqueue_missing_chunks(needed_chunks)
	_enqueue_distant_chunks()


func _collect_needed_chunks(out: Dictionary) -> void:
	for player in _players_node.get_children():
		var chunk_coord: Vector2i = _world_to_chunk(player.global_position)
		for dy in range(-GameConstants.CHUNK_LOAD_RADIUS, GameConstants.CHUNK_LOAD_RADIUS + 1):
			for dx in range(-GameConstants.CHUNK_LOAD_RADIUS, GameConstants.CHUNK_LOAD_RADIUS + 1):
				out[Vector2i(chunk_coord.x + dx, chunk_coord.y + dy)] = true


func _enqueue_missing_chunks(needed: Dictionary) -> void:
	for coord: Vector2i in needed:
		if not loaded_chunks.has(coord) and coord not in _load_queue:
			_load_queue.append(coord)


func _enqueue_distant_chunks() -> void:
	for coord: Vector2i in loaded_chunks:
		if _is_beyond_unload_radius(coord) and coord not in _unload_queue:
			_unload_queue.append(coord)


func _process_load_queue() -> void:
	var count := 0
	while _load_queue.size() > 0 and count < GameConstants.CHUNKS_PER_FRAME:
		var coord: Vector2i = _load_queue.pop_front()
		if loaded_chunks.has(coord):
			continue

		if multiplayer.is_server():
			var chunk: ChunkData = _generate_and_restore(coord)
			_apply_chunk(chunk)
		else:
			_request_chunk.rpc_id(1, coord.x, coord.y)
			loaded_chunks[coord] = null

		count += 1

	if DEBUG_LOG and count > 0:
		print("[ChunkManager] Loaded %d chunk(s) - total: %d" % [count, loaded_chunks.size()])


func _process_unload_queue() -> void:
	var count := 0
	while _unload_queue.size() > 0 and count < GameConstants.CHUNKS_PER_FRAME:
		var coord: Vector2i = _unload_queue.pop_front()
		if not loaded_chunks.has(coord):
			continue
		_erase_chunk(coord)
		count += 1

	if DEBUG_LOG and count > 0:
		print("[ChunkManager] Unloaded %d chunk(s) - total: %d" % [count, loaded_chunks.size()])


func _is_beyond_unload_radius(coord: Vector2i) -> bool:
	if _players_node.get_child_count() == 0:
		return false
	for player in _players_node.get_children():
		var player_chunk: Vector2i = _world_to_chunk(player.global_position)
		if (
			absi(coord.x - player_chunk.x) <= GameConstants.CHUNK_UNLOAD_RADIUS
			and absi(coord.y - player_chunk.y) <= GameConstants.CHUNK_UNLOAD_RADIUS
		):
			return false
	return true


func _apply_chunk(chunk: ChunkData) -> void:
	loaded_chunks[chunk.chunk_coord] = chunk
	var origin_x: int = chunk.chunk_coord.x * GameConstants.CHUNK_SIZE
	var origin_y: int = chunk.chunk_coord.y * GameConstants.CHUNK_SIZE

	for local_y in range(GameConstants.CHUNK_SIZE):
		for local_x in range(GameConstants.CHUNK_SIZE):
			var cell := Vector2i(origin_x + local_x, origin_y + local_y)
			_apply_ground_cell(cell, chunk.get_ground_tile(local_x, local_y))
			_apply_cell(cell, chunk.get_top_tile(local_x, local_y))

	if world_object_manager != null and world_object_manager.has_method("apply_chunk_objects"):
		world_object_manager.apply_chunk_objects(chunk)


func _erase_chunk(coord: Vector2i) -> void:
	if multiplayer.is_server():
		var chunk := loaded_chunks.get(coord) as ChunkData
		if chunk != null:
			SaveManager.save_chunk(coord, chunk)

	var origin_x: int = coord.x * GameConstants.CHUNK_SIZE
	var origin_y: int = coord.y * GameConstants.CHUNK_SIZE
	for local_y in range(GameConstants.CHUNK_SIZE):
		for local_x in range(GameConstants.CHUNK_SIZE):
			var cell := Vector2i(origin_x + local_x, origin_y + local_y)
			if ground_layer != null:
				ground_layer.erase_cell(cell)
			if ground_collision_layer != null:
				ground_collision_layer.erase_cell(cell)
			if liquid_layer != null:
				liquid_layer.erase_cell(cell)
			terrain_layer.erase_cell(cell)
			base_visual_layer.erase_cell(cell)
			decor_layer.erase_cell(cell)
			_erase_tall_structure_visual(cell)

	if world_object_manager != null and world_object_manager.has_method("clear_chunk_objects"):
		world_object_manager.clear_chunk_objects(coord)

	loaded_chunks.erase(coord)


func _generate_and_restore(coord: Vector2i) -> ChunkData:
	var chunk: ChunkData = world_generator.generate_chunk(coord)
	var saved: Dictionary = SaveManager.load_chunk_modifications(coord)
	if saved.has("top"):
		chunk.top_modifications = saved.get("top", {})
		chunk.ground_modifications = saved.get("ground", {})
	elif not saved.is_empty():
		chunk.top_modifications = saved

	if world_object_manager != null and world_object_manager.has_method("apply_saved_world_object_modifications"):
		world_object_manager.apply_saved_world_object_modifications(chunk, saved)

	_migrate_legacy_prop_modifications(chunk)
	return chunk


func _world_to_chunk(world_pos: Vector2) -> Vector2i:
	var tile_x: int = floori(world_pos.x / GameConstants.TILE_SIZE)
	var tile_y: int = floori(world_pos.y / GameConstants.TILE_SIZE)
	return Vector2i(
		floori(float(tile_x) / GameConstants.CHUNK_SIZE),
		floori(float(tile_y) / GameConstants.CHUNK_SIZE),
	)


@rpc("any_peer", "reliable")
func _request_chunk(cx: int, cy: int) -> void:
	if not multiplayer.is_server():
		return

	var coord := Vector2i(cx, cy)
	var chunk: ChunkData
	if loaded_chunks.has(coord) and loaded_chunks[coord] != null:
		chunk = loaded_chunks[coord]
	else:
		chunk = _generate_and_restore(coord)
		_apply_chunk(chunk)

	var sender_id: int = multiplayer.get_remote_sender_id()
	if DEBUG_LOG:
		print("[ChunkManager] Sending chunk %s to peer %d" % [coord, sender_id])
	_receive_chunk.rpc_id(sender_id, chunk.serialize())


@rpc("authority", "reliable")
func _receive_chunk(data: PackedByteArray) -> void:
	var chunk := ChunkData.deserialize(data)
	if DEBUG_LOG:
		print("[ChunkManager] Received chunk %s from host" % chunk.chunk_coord)
	_apply_chunk(chunk)


func break_tile(coord: Vector2i) -> void:
	if multiplayer.is_server():
		var tile_id := get_top_tile_at(coord)
		_do_break_tile(coord)
		_sync_break_tile.rpc(coord.x, coord.y)
		GameEvents.block_broken.emit(coord, tile_id)
	else:
		_request_break_tile.rpc_id(1, coord.x, coord.y)


func _do_break_tile(coord: Vector2i) -> void:
	var chunk_coord := _cell_to_chunk(coord)
	var chunk := loaded_chunks.get(chunk_coord) as ChunkData
	if chunk != null:
		var local := _world_to_local(coord, chunk_coord)
		chunk.set_top_modification(local.x, local.y, TileProperties.EMPTY)
	_apply_cell(coord, TileProperties.EMPTY)


@rpc("any_peer", "reliable")
func _request_break_tile(tx: int, ty: int) -> void:
	if not multiplayer.is_server():
		return
	var coord := Vector2i(tx, ty)
	var tile_id := get_top_tile_at(coord)
	if tile_id == TileProperties.EMPTY:
		return

	_do_break_tile(coord)
	_sync_break_tile.rpc(tx, ty)
	GameEvents.block_broken.emit(coord, tile_id)


@rpc("authority", "reliable")
func _sync_break_tile(tx: int, ty: int) -> void:
	var coord := Vector2i(tx, ty)
	var tile_id := get_top_tile_at(coord)
	_do_break_tile(coord)
	GameEvents.block_broken.emit(coord, tile_id)


func can_support_world_object_at(coord: Vector2i) -> bool:
	if get_top_tile_at(coord) != TileProperties.EMPTY:
		return false
	var ground_id := get_ground_tile_at(coord)
	var ground_props := GroundTileProperties.get_properties(ground_id)
	return ground_props != null and ground_props.is_solid


func can_place_top_tile_at(coord: Vector2i) -> bool:
	if get_top_tile_at(coord) != TileProperties.EMPTY:
		return false
	if world_object_manager != null and world_object_manager.has_method("is_cell_occupied"):
		if world_object_manager.is_cell_occupied(coord):
			return false
	var ground_id := get_ground_tile_at(coord)
	var ground_props := GroundTileProperties.get_properties(ground_id)
	return ground_props != null and ground_props.is_solid


func place_tile(coord: Vector2i, tile_id: int) -> void:
	if not multiplayer.is_server():
		return
	var resolved_tile_id := TileProperties.resolve_placement_tile_id(tile_id)
	_do_place_tile(coord, resolved_tile_id)
	_sync_place_tile.rpc(coord.x, coord.y, resolved_tile_id)
	GameEvents.block_placed.emit(coord, resolved_tile_id)


func _do_place_tile(coord: Vector2i, tile_id: int) -> void:
	var props := TileProperties.get_properties(tile_id)
	if props == null:
		return

	var chunk_coord := _cell_to_chunk(coord)
	var chunk := loaded_chunks.get(chunk_coord) as ChunkData
	if chunk != null:
		var local := _world_to_local(coord, chunk_coord)
		chunk.set_top_modification(local.x, local.y, tile_id)
	_apply_cell(coord, tile_id)


@rpc("authority", "reliable")
func _sync_place_tile(tx: int, ty: int, tile_id: int) -> void:
	_do_place_tile(Vector2i(tx, ty), tile_id)


func _apply_cell(cell: Vector2i, tile_id: int) -> void:
	var props := TileProperties.get_properties(tile_id)
	if props == null:
		terrain_layer.erase_cell(cell)
		base_visual_layer.erase_cell(cell)
		decor_layer.erase_cell(cell)
		_erase_tall_structure_visual(cell)
	else:
		terrain_layer.set_cell(cell, 0, props.atlas_coord)

		if props.uses_sway_decor_layer():
			decor_layer.set_cell(cell, 0, props.atlas_coord)
			base_visual_layer.erase_cell(cell)
		else:
			decor_layer.erase_cell(cell)

		if props.uses_node_based_world_visual():
			base_visual_layer.erase_cell(cell)
			_erase_tall_structure_visual(cell)
		elif props.uses_sway_decor_layer():
			_erase_tall_structure_visual(cell)
		else:
			base_visual_layer.set_cell(cell, 0, props.atlas_coord)
			_erase_tall_structure_visual(cell)

	_sync_tall_structure_visual(cell)


func _sync_tall_structure_visual(coord: Vector2i) -> void:
	var tile_id := get_top_tile_at(coord)
	var props := TileProperties.get_properties(tile_id)
	if props == null or not props.uses_node_based_world_visual():
		_erase_tall_structure_visual(coord)
		return
	_ensure_tall_structure_visual(coord, props)


func _ensure_tall_structure_visual(coord: Vector2i, props: TileProperties) -> void:
	var key := _cell_key(coord)
	var visual := _tall_structure_visuals.get(key) as TallStructureVisual
	if visual == null:
		visual = TALL_STRUCTURE_VISUAL_SCENE.instantiate()
		visual.name = "TallStructure_%s_%s" % [coord.x, coord.y]
		visual.configure_parts(props.build_world_visual_parts(GameConstants.TILE_SIZE), false)
		tall_structure_visuals_node.add_child(visual)
		_tall_structure_visuals[key] = visual

	visual.position = Vector2(
		coord.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
		(coord.y + 1) * GameConstants.TILE_SIZE
	)
	visual.configure_parts(props.build_world_visual_parts(GameConstants.TILE_SIZE), false)
	breakable_world_visual_created.emit(_tile_target_key(coord), visual)


func _erase_tall_structure_visual(coord: Vector2i) -> void:
	var key := _cell_key(coord)
	var visual := _tall_structure_visuals.get(key) as TallStructureVisual
	if visual == null:
		return
	_tall_structure_visuals.erase(key)
	visual.queue_free()


func _apply_ground_cell(cell: Vector2i, ground_id: int) -> void:
	var props := GroundTileProperties.get_properties(ground_id)
	if props == null:
		if ground_layer != null:
			ground_layer.erase_cell(cell)
		if ground_collision_layer != null:
			ground_collision_layer.set_cell(cell, 0, Vector2i.ZERO)
		if liquid_layer != null:
			liquid_layer.erase_cell(cell)
	elif props.is_liquid:
		if ground_layer != null:
			ground_layer.erase_cell(cell)
		if ground_collision_layer != null:
			ground_collision_layer.set_cell(cell, 0, Vector2i.ZERO)
		if liquid_layer != null:
			liquid_layer.set_cell(cell, 0, props.atlas_coord)
	else:
		if ground_layer != null:
			ground_layer.set_cell(cell, 0, props.atlas_coord)
		if ground_collision_layer != null:
			ground_collision_layer.erase_cell(cell)
		if liquid_layer != null:
			liquid_layer.erase_cell(cell)


func get_breakable_tile_visual(coord: Vector2i) -> TallStructureVisual:
	var visual := _tall_structure_visuals.get(_cell_key(coord)) as TallStructureVisual
	if visual == null or not is_instance_valid(visual):
		return null
	return visual


func get_top_tile_at(coord: Vector2i) -> int:
	var chunk_coord := _cell_to_chunk(coord)
	var chunk := loaded_chunks.get(chunk_coord) as ChunkData
	if chunk == null:
		return TileProperties.EMPTY
	var local := _world_to_local(coord, chunk_coord)
	return chunk.get_top_tile(local.x, local.y)


func get_ground_tile_at(coord: Vector2i) -> int:
	var chunk_coord := _cell_to_chunk(coord)
	var chunk := loaded_chunks.get(chunk_coord) as ChunkData
	if chunk == null:
		return GroundTileProperties.EMPTY
	var local := _world_to_local(coord, chunk_coord)
	return chunk.get_ground_tile(local.x, local.y)


func _migrate_legacy_prop_modifications(chunk: ChunkData) -> void:
	var top_keys := chunk.top_modifications.keys()
	for key_variant in top_keys:
		var key := int(key_variant)
		var tile_id := int(
			chunk.top_modifications.get(key_variant, chunk.top_modifications.get(key, TileProperties.EMPTY))
		)
		var prop_id := _legacy_prop_id_from_tile_id(tile_id)
		if prop_id == int(_world_prop_catalog.get("EMPTY")):
			continue

		var definition = _world_object_catalog.call("get_definition_by_prop_id", prop_id)
		if definition == null:
			continue

		var local_origin := Vector2i(
			key % GameConstants.CHUNK_SIZE,
			floori(float(key) / float(GameConstants.CHUNK_SIZE))
		)
		chunk.add_world_object_addition(local_origin, definition.id)
		chunk.top_modifications.erase(key_variant)
		if key_variant != key:
			chunk.top_modifications.erase(key)


func _legacy_prop_id_from_tile_id(tile_id: int) -> int:
	var tile_props := TileProperties.get_properties(tile_id)
	if tile_props == null:
		return int(_world_prop_catalog.get("EMPTY"))
	var by_name: Dictionary = _world_prop_catalog.get("by_name")
	return int(by_name.get(tile_props.name, _world_prop_catalog.get("EMPTY")))


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


func _cell_key(coord: Vector2i) -> String:
	return "%s:%s" % [coord.x, coord.y]


func _tile_target_key(coord: Vector2i) -> String:
	return "tile:%s:%s" % [coord.x, coord.y]
