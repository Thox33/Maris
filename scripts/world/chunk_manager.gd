extends Node
## Orchestrates chunk loading, unloading, and network synchronization.
## Periodically checks player positions and loads/unloads chunks as needed.
## Host generates chunks from noise; clients request them via RPC.

const TALL_STRUCTURE_VISUAL_SCENE := preload("res://scenes/world/tall_structure_visual.tscn")

## Set to false to silence chunk load/unload messages in the console.
const DEBUG_LOG: bool = false

## Reference to the parent WorldGenerator (set by setup()).
var world_generator: Node2D

## Ground-layer TileMapLayer — renders the base floor behind everything.
var ground_layer: TileMapLayer

## Reference to the global TileMapLayer.
var terrain_layer: TileMapLayer
var base_visual_layer: TileMapLayer

## Depth-sorted decor tiles live here so they can interleave with actors.
var decor_layer: TileMapLayer

var tall_structure_visuals_node: Node2D
var _tall_structure_visuals: Dictionary = {}

## Currently loaded chunks. Key = Vector2i (chunk coord), Value = ChunkData.
var loaded_chunks: Dictionary = {}

## Timer accumulator for periodic updates.
var _update_timer: float = 0.0

## Reference to the Players node for position checks.
var _players_node: Node

## Queues for spreading chunk work across frames.
var _load_queue: Array[Vector2i] = []
var _unload_queue: Array[Vector2i] = []


func setup(
	p_world_generator: Node2D,
	p_ground_layer: TileMapLayer,
	p_terrain_layer: TileMapLayer,
	p_base_visual_layer: TileMapLayer,
	p_decor_layer: TileMapLayer,
	p_tall_structure_visuals_node: Node2D,
	p_players_node: Node,
) -> void:
	world_generator = p_world_generator
	ground_layer = p_ground_layer
	terrain_layer = p_terrain_layer
	base_visual_layer = p_base_visual_layer
	decor_layer = p_decor_layer
	tall_structure_visuals_node = p_tall_structure_visuals_node
	_players_node = p_players_node


## Immediately loads all chunks in LOAD_RADIUS around a world position.
## Call this before spawning a player so terrain + collisions exist on frame 1.
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
	# Process queued work every frame (limited per frame to avoid spikes).
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
	_enqueue_distant_chunks(needed_chunks)


## Gathers all chunk coords that should be loaded based on player positions.
func _collect_needed_chunks(out: Dictionary) -> void:
	for player in _players_node.get_children():
		var chunk_coord: Vector2i = _world_to_chunk(player.global_position)
		for dy in range(-GameConstants.CHUNK_LOAD_RADIUS, GameConstants.CHUNK_LOAD_RADIUS + 1):
			for dx in range(-GameConstants.CHUNK_LOAD_RADIUS, GameConstants.CHUNK_LOAD_RADIUS + 1):
				out[Vector2i(chunk_coord.x + dx, chunk_coord.y + dy)] = true


## Adds missing chunks to the load queue (avoids duplicates).
func _enqueue_missing_chunks(needed: Dictionary) -> void:
	for coord: Vector2i in needed:
		if not loaded_chunks.has(coord) and coord not in _load_queue:
			_load_queue.append(coord)


## Adds distant chunks to the unload queue (avoids duplicates).
func _enqueue_distant_chunks(_needed: Dictionary) -> void:
	for coord: Vector2i in loaded_chunks:
		if _is_beyond_unload_radius(coord) and coord not in _unload_queue:
			_unload_queue.append(coord)


## Processes up to CHUNKS_PER_FRAME load operations per frame.
func _process_load_queue() -> void:
	var count: int = 0
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


## Processes up to CHUNKS_PER_FRAME unload operations per frame.
func _process_unload_queue() -> void:
	var count: int = 0
	while _unload_queue.size() > 0 and count < GameConstants.CHUNKS_PER_FRAME:
		var coord: Vector2i = _unload_queue.pop_front()
		if not loaded_chunks.has(coord):
			continue
		_erase_chunk(coord)
		count += 1

	if DEBUG_LOG and count > 0:
		print("[ChunkManager] Unloaded %d chunk(s) - total: %d" % [count, loaded_chunks.size()])


## Checks if a chunk coord is beyond unload radius of ALL players.
## If no players exist yet (e.g. deferred spawn or dedicated server), keep all chunks.
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


## Writes a chunk's tiles into the TileMapLayer and stores it.
func _apply_chunk(chunk: ChunkData) -> void:
	loaded_chunks[chunk.chunk_coord] = chunk
	var origin_x: int = chunk.chunk_coord.x * GameConstants.CHUNK_SIZE
	var origin_y: int = chunk.chunk_coord.y * GameConstants.CHUNK_SIZE

	for local_y in range(GameConstants.CHUNK_SIZE):
		for local_x in range(GameConstants.CHUNK_SIZE):
			var cell := Vector2i(origin_x + local_x, origin_y + local_y)
			_apply_ground_cell(cell, chunk.get_ground_tile(local_x, local_y))
			_apply_cell(cell, chunk.get_top_tile(local_x, local_y))


## Erases a chunk's tiles from the TileMapLayer and removes it from the cache.
## Server persists modifications to disk before erasing.
func _erase_chunk(coord: Vector2i) -> void:
	# Persist modifications before discarding the chunk from memory.
	if multiplayer.is_server():
		var chunk: ChunkData = loaded_chunks.get(coord)
		if chunk != null:
			SaveManager.save_chunk(coord, chunk)

	var origin_x: int = coord.x * GameConstants.CHUNK_SIZE
	var origin_y: int = coord.y * GameConstants.CHUNK_SIZE

	for local_y in range(GameConstants.CHUNK_SIZE):
		for local_x in range(GameConstants.CHUNK_SIZE):
			var cell := Vector2i(origin_x + local_x, origin_y + local_y)
			if ground_layer != null:
				ground_layer.erase_cell(cell)
			terrain_layer.erase_cell(cell)
			base_visual_layer.erase_cell(cell)
			decor_layer.erase_cell(cell)
			_erase_tall_structure_visual(cell)

	loaded_chunks.erase(coord)


## Generates a chunk from noise and restores any saved modifications from disk.
func _generate_and_restore(coord: Vector2i) -> ChunkData:
	var chunk: ChunkData = world_generator.generate_chunk(coord)
	var saved: Dictionary = SaveManager.load_chunk_modifications(coord)
	if saved.has("top"):
		chunk.top_modifications = saved["top"]
	if saved.has("ground"):
		chunk.ground_modifications = saved["ground"]
	return chunk


## Converts a world-space pixel position to a chunk coordinate.
func _world_to_chunk(world_pos: Vector2) -> Vector2i:
	var tile_x: int = floori(world_pos.x / GameConstants.TILE_SIZE)
	var tile_y: int = floori(world_pos.y / GameConstants.TILE_SIZE)
	return Vector2i(
		floori(float(tile_x) / GameConstants.CHUNK_SIZE),
		floori(float(tile_y) / GameConstants.CHUNK_SIZE),
	)


# --- Network RPCs ---

## Client requests a chunk from the host.
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


## Client receives chunk data from the host.
@rpc("authority", "reliable")
func _receive_chunk(data: PackedByteArray) -> void:
	var chunk: ChunkData = ChunkData.deserialize(data)
	if DEBUG_LOG:
		print("[ChunkManager] Received chunk %s from host" % chunk.chunk_coord)
	_apply_chunk(chunk)


# --- Block breaking RPCs ---


## Called locally by BlockInteraction when a tile is fully broken.
func break_tile(coord: Vector2i) -> void:
	if multiplayer.is_server():
		var tile_id: int = get_top_tile_at(coord)
		_do_break_tile(coord)
		_sync_break_tile.rpc(coord.x, coord.y)
		GameEvents.block_broken.emit(coord, tile_id)
	else:
		_request_break_tile.rpc_id(1, coord.x, coord.y)


## Erases a top tile and records the modification in chunk data.
func _do_break_tile(coord: Vector2i) -> void:
	var chunk_x: int = floori(float(coord.x) / GameConstants.CHUNK_SIZE)
	var chunk_y: int = floori(float(coord.y) / GameConstants.CHUNK_SIZE)
	var chunk_coord := Vector2i(chunk_x, chunk_y)
	if loaded_chunks.has(chunk_coord) and loaded_chunks[chunk_coord] != null:
		var local_x: int = coord.x - chunk_x * GameConstants.CHUNK_SIZE
		var local_y: int = coord.y - chunk_y * GameConstants.CHUNK_SIZE
		var chunk: ChunkData = loaded_chunks[chunk_coord]
		chunk.set_top_modification(local_x, local_y, -1)

	_apply_cell(coord, TileProperties.EMPTY)


## Client asks host to break a tile.
@rpc("any_peer", "reliable")
func _request_break_tile(tx: int, ty: int) -> void:
	if not multiplayer.is_server():
		return
	var coord := Vector2i(tx, ty)
	var tile_id: int = get_top_tile_at(coord)
	if tile_id == TileProperties.EMPTY:
		return

	_do_break_tile(coord)
	_sync_break_tile.rpc(tx, ty)
	GameEvents.block_broken.emit(coord, tile_id)


## Host tells all clients a tile was broken.
@rpc("authority", "reliable")
func _sync_break_tile(tx: int, ty: int) -> void:
	var coord := Vector2i(tx, ty)
	var tile_id: int = get_top_tile_at(coord)
	_do_break_tile(coord)
	GameEvents.block_broken.emit(coord, tile_id)


# --- Block placing ---


## Returns true if a top tile can be placed at this coordinate.
## Requires: top layer is empty AND ground layer is solid (not void/liquid).
func is_cell_empty(coord: Vector2i) -> bool:
	if get_top_tile_at(coord) != TileProperties.EMPTY:
		return false
	var ground_id: int = get_ground_tile_at(coord)
	var ground_props := GroundTileProperties.get_properties(ground_id)
	return ground_props != null and ground_props.is_solid


## Server-only: places a tile and syncs to all clients.
func place_tile(coord: Vector2i, tile_id: int) -> void:
	if not multiplayer.is_server():
		return
	var resolved_tile_id: int = TileProperties.resolve_placement_tile_id(tile_id)
	_do_place_tile(coord, resolved_tile_id)
	_sync_place_tile.rpc(coord.x, coord.y, resolved_tile_id)
	GameEvents.block_placed.emit(coord, resolved_tile_id)


## Writes a single tile into the TileMapLayer and records the modification.
func _do_place_tile(coord: Vector2i, tile_id: int) -> void:
	var props := TileProperties.get_properties(tile_id)
	if props == null:
		return

	# Record modification in top layer chunk data.
	var chunk_x: int = floori(float(coord.x) / GameConstants.CHUNK_SIZE)
	var chunk_y: int = floori(float(coord.y) / GameConstants.CHUNK_SIZE)
	var chunk_coord := Vector2i(chunk_x, chunk_y)
	if loaded_chunks.has(chunk_coord) and loaded_chunks[chunk_coord] != null:
		var local_x: int = coord.x - chunk_x * GameConstants.CHUNK_SIZE
		var local_y: int = coord.y - chunk_y * GameConstants.CHUNK_SIZE
		var chunk: ChunkData = loaded_chunks[chunk_coord]
		chunk.set_top_modification(local_x, local_y, tile_id)

	_apply_cell(coord, tile_id)


## Host tells all clients a tile was placed.
@rpc("authority", "reliable")
func _sync_place_tile(tx: int, ty: int, tile_id: int) -> void:
	_do_place_tile(Vector2i(tx, ty), tile_id)


## Places or erases a single cell on terrain/base/decor layers.
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
	var tile_id: int = get_top_tile_at(coord)
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


func _erase_tall_structure_visual(coord: Vector2i) -> void:
	var key := _cell_key(coord)
	var visual := _tall_structure_visuals.get(key) as TallStructureVisual
	if visual == null:
		return
	_tall_structure_visuals.erase(key)
	visual.queue_free()


## Places or erases a single cell on the ground layer.
func _apply_ground_cell(cell: Vector2i, ground_id: int) -> void:
	if ground_layer == null:
		return
	var props := GroundTileProperties.get_properties(ground_id)
	if props == null:
		ground_layer.erase_cell(cell)
	else:
		ground_layer.set_cell(cell, 0, props.atlas_coord)


func _cell_key(coord: Vector2i) -> String:
	return "%s:%s" % [coord.x, coord.y]


## Returns the top tile ID at a world-space tile coordinate from chunk data.
func get_top_tile_at(coord: Vector2i) -> int:
	var chunk_x: int = floori(float(coord.x) / GameConstants.CHUNK_SIZE)
	var chunk_y: int = floori(float(coord.y) / GameConstants.CHUNK_SIZE)
	var chunk_coord := Vector2i(chunk_x, chunk_y)
	var chunk: ChunkData = loaded_chunks.get(chunk_coord)
	if chunk == null:
		return TileProperties.EMPTY
	var local_x: int = coord.x - chunk_x * GameConstants.CHUNK_SIZE
	var local_y: int = coord.y - chunk_y * GameConstants.CHUNK_SIZE
	return chunk.get_top_tile(local_x, local_y)


## Returns the ground tile ID at a world-space tile coordinate from chunk data.
func get_ground_tile_at(coord: Vector2i) -> int:
	var chunk_x: int = floori(float(coord.x) / GameConstants.CHUNK_SIZE)
	var chunk_y: int = floori(float(coord.y) / GameConstants.CHUNK_SIZE)
	var chunk_coord := Vector2i(chunk_x, chunk_y)
	var chunk: ChunkData = loaded_chunks.get(chunk_coord)
	if chunk == null:
		return GroundTileProperties.EMPTY
	var local_x: int = coord.x - chunk_x * GameConstants.CHUNK_SIZE
	var local_y: int = coord.y - chunk_y * GameConstants.CHUNK_SIZE
	return chunk.get_ground_tile(local_x, local_y)
