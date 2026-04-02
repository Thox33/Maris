extends Node
## Orchestrates chunk loading, unloading, and network synchronization.
## Periodically checks player positions and loads/unloads chunks as needed.
## Host generates chunks from noise; clients request them via RPC.

## Set to false to silence chunk load/unload messages in the console.
const DEBUG_LOG: bool = false

## Reference to the parent WorldGenerator (set in _ready).
var world_generator: Node2D

## Reference to the global TileMapLayer.
var terrain_layer: TileMapLayer

## PlantLayer mirror — coral tiles are duplicated here for the sway shader.
var plant_layer: TileMapLayer

## Currently loaded chunks. Key = Vector2i (chunk coord), Value = ChunkData.
var loaded_chunks: Dictionary = {}

## Timer accumulator for periodic updates.
var _update_timer: float = 0.0

## Reference to the Players node for position checks.
var _players_node: Node

## Queues for spreading chunk work across frames.
var _load_queue: Array[Vector2i] = []
var _unload_queue: Array[Vector2i] = []


func _ready() -> void:
	world_generator = get_parent()
	terrain_layer = world_generator.get_node("TerrainLayer")
	plant_layer = world_generator.get_node("PlantLayer")
	_players_node = null


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
				var chunk: ChunkData = world_generator.generate_chunk(coord)
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

	# Lazily find the Players node.
	if _players_node == null:
		_players_node = get_tree().get_root().get_node_or_null("Main/Players")
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
			var chunk: ChunkData = world_generator.generate_chunk(coord)
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
			var tile_id: int = chunk.get_tile(local_x, local_y)
			var cell := Vector2i(origin_x + local_x, origin_y + local_y)
			_apply_cell(cell, tile_id)


## Erases a chunk's tiles from the TileMapLayer and removes it from the cache.
func _erase_chunk(coord: Vector2i) -> void:
	var origin_x: int = coord.x * GameConstants.CHUNK_SIZE
	var origin_y: int = coord.y * GameConstants.CHUNK_SIZE

	for local_y in range(GameConstants.CHUNK_SIZE):
		for local_x in range(GameConstants.CHUNK_SIZE):
			var cell := Vector2i(origin_x + local_x, origin_y + local_y)
			terrain_layer.erase_cell(cell)
			plant_layer.erase_cell(cell)

	loaded_chunks.erase(coord)


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
		chunk = world_generator.generate_chunk(coord)
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
		# Determine tile/item BEFORE erasing.
		var tile_id: int = get_tile_at(coord)

		_do_break_tile(coord)
		_sync_break_tile.rpc(coord.x, coord.y)

		# Spawn item drop (use drop_tile_id so variants drop the base item).
		var props := TileProperties.get_properties(tile_id)
		var drop_id: int = props.drop_tile_id if props else tile_id
		var item_id: int = ItemProperties.from_tile(drop_id)
		if item_id != ItemProperties.NONE:
			var main_node := get_tree().get_root().get_node_or_null("Main")
			if main_node and main_node.has_method("spawn_item_drop"):
				var tile_center := Vector2(
					coord.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
					coord.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0
				)
				main_node.spawn_item_drop(item_id, 1, tile_center)
	else:
		_request_break_tile.rpc_id(1, coord.x, coord.y)


## Erases a single tile and records the modification in chunk data.
func _do_break_tile(coord: Vector2i) -> void:
	terrain_layer.erase_cell(coord)
	plant_layer.erase_cell(coord)

	var chunk_x: int = floori(float(coord.x) / GameConstants.CHUNK_SIZE)
	var chunk_y: int = floori(float(coord.y) / GameConstants.CHUNK_SIZE)
	var chunk_coord := Vector2i(chunk_x, chunk_y)
	if loaded_chunks.has(chunk_coord) and loaded_chunks[chunk_coord] != null:
		var local_x: int = coord.x - chunk_x * GameConstants.CHUNK_SIZE
		var local_y: int = coord.y - chunk_y * GameConstants.CHUNK_SIZE
		var chunk: ChunkData = loaded_chunks[chunk_coord]
		chunk.set_modification(local_x, local_y, -1)


## Client asks host to break a tile.
@rpc("any_peer", "reliable")
func _request_break_tile(tx: int, ty: int) -> void:
	if not multiplayer.is_server():
		return
	var coord := Vector2i(tx, ty)
	var tile_id: int = get_tile_at(coord)
	if tile_id == TileProperties.EMPTY:
		return

	_do_break_tile(coord)
	_sync_break_tile.rpc(tx, ty)

	# Spawn an item drop (use drop_tile_id so variants drop the base item).
	var props := TileProperties.get_properties(tile_id)
	var drop_id: int = props.drop_tile_id if props else tile_id
	var item_id: int = ItemProperties.from_tile(drop_id)
	if item_id != ItemProperties.NONE:
		var main_node := get_tree().get_root().get_node_or_null("Main")
		if main_node and main_node.has_method("spawn_item_drop"):
			var tile_center := Vector2(
				tx * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
				ty * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0
			)
			main_node.spawn_item_drop(item_id, 1, tile_center)


## Host tells all clients a tile was broken.
@rpc("authority", "reliable")
func _sync_break_tile(tx: int, ty: int) -> void:
	_do_break_tile(Vector2i(tx, ty))


# --- Block placing ---


## Returns true if a tile coordinate has no block (is empty water).
func is_cell_empty(coord: Vector2i) -> bool:
	return get_tile_at(coord) == TileProperties.EMPTY


## Server-only: places a tile and syncs to all clients.
func place_tile(coord: Vector2i, tile_id: int) -> void:
	if not multiplayer.is_server():
		return
	_do_place_tile(coord, tile_id)
	_sync_place_tile.rpc(coord.x, coord.y, tile_id)


## Writes a single tile into the TileMapLayer and records the modification.
func _do_place_tile(coord: Vector2i, tile_id: int) -> void:
	var props := TileProperties.get_properties(tile_id)
	if props == null:
		return

	_apply_cell(coord, tile_id)

	# Record modification in chunk data.
	var chunk_x: int = floori(float(coord.x) / GameConstants.CHUNK_SIZE)
	var chunk_y: int = floori(float(coord.y) / GameConstants.CHUNK_SIZE)
	var chunk_coord := Vector2i(chunk_x, chunk_y)
	if loaded_chunks.has(chunk_coord) and loaded_chunks[chunk_coord] != null:
		var local_x: int = coord.x - chunk_x * GameConstants.CHUNK_SIZE
		var local_y: int = coord.y - chunk_y * GameConstants.CHUNK_SIZE
		var chunk: ChunkData = loaded_chunks[chunk_coord]
		chunk.set_modification(local_x, local_y, tile_id)


## Host tells all clients a tile was placed.
@rpc("authority", "reliable")
func _sync_place_tile(tx: int, ty: int, tile_id: int) -> void:
	_do_place_tile(Vector2i(tx, ty), tile_id)


## Places or erases a single cell on terrain_layer (+ plant_layer mirror).
func _apply_cell(cell: Vector2i, tile_id: int) -> void:
	var props := TileProperties.get_properties(tile_id)
	if props == null:
		terrain_layer.erase_cell(cell)
		plant_layer.erase_cell(cell)
		return

	terrain_layer.set_cell(cell, 0, props.atlas_coord)

	if props.plant:
		plant_layer.set_cell(cell, 0, props.atlas_coord)
	else:
		plant_layer.erase_cell(cell)


## Returns the tile ID at a world-space tile coordinate from chunk data.
func get_tile_at(coord: Vector2i) -> int:
	var chunk_x: int = floori(float(coord.x) / GameConstants.CHUNK_SIZE)
	var chunk_y: int = floori(float(coord.y) / GameConstants.CHUNK_SIZE)
	var chunk_coord := Vector2i(chunk_x, chunk_y)
	var chunk: ChunkData = loaded_chunks.get(chunk_coord)
	if chunk == null:
		return TileProperties.EMPTY

	var local_x: int = coord.x - chunk_x * GameConstants.CHUNK_SIZE
	var local_y: int = coord.y - chunk_y * GameConstants.CHUNK_SIZE
	return chunk.get_tile(local_x, local_y)
