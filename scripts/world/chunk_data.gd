class_name ChunkData
extends Resource

## Data structure for a single 16x16 chunk of the world.
## Each cell holds two independent tile slots:
##   ground - the floor (GroundTileProperties ID, -1 = void/chasm)
##   top    - what sits on the floor (TileProperties ID, -1 = empty)
## Static world objects are anchored per chunk and stored as:
##   - generated base objects
##   - player additions
##   - removals against generated base objects

var chunk_coord: Vector2i
var ground_base_tiles: PackedInt32Array
var top_base_tiles: PackedInt32Array
var base_world_objects: Dictionary = {}
var ground_modifications: Dictionary = {}
var top_modifications: Dictionary = {}
var world_object_additions: Dictionary = {}
var world_object_removals: Dictionary = {}


func _init(coord: Vector2i = Vector2i.ZERO) -> void:
	chunk_coord = coord
	var size: int = GameConstants.CHUNK_SIZE * GameConstants.CHUNK_SIZE
	ground_base_tiles = PackedInt32Array()
	ground_base_tiles.resize(size)
	ground_base_tiles.fill(-1)
	top_base_tiles = PackedInt32Array()
	top_base_tiles.resize(size)
	top_base_tiles.fill(-1)


func get_ground_tile(local_x: int, local_y: int) -> int:
	var idx: int = local_y * GameConstants.CHUNK_SIZE + local_x
	if ground_modifications.has(idx):
		return ground_modifications[idx]
	return ground_base_tiles[idx]


func get_top_tile(local_x: int, local_y: int) -> int:
	var idx: int = local_y * GameConstants.CHUNK_SIZE + local_x
	if top_modifications.has(idx):
		return top_modifications[idx]
	return top_base_tiles[idx]


func set_top_modification(local_x: int, local_y: int, tile_id: int) -> void:
	var idx: int = local_y * GameConstants.CHUNK_SIZE + local_x
	top_modifications[idx] = tile_id


func set_ground_modification(local_x: int, local_y: int, ground_id: int) -> void:
	var idx: int = local_y * GameConstants.CHUNK_SIZE + local_x
	ground_modifications[idx] = ground_id


func add_base_world_object(local_origin: Vector2i, object_id: String) -> void:
	base_world_objects[build_world_object_key(object_id, local_origin)] = {
		"object_id": object_id,
		"origin_x": local_origin.x,
		"origin_y": local_origin.y,
	}


func get_effective_world_objects() -> Dictionary:
	var effective: Dictionary = {}
	for key in base_world_objects.keys():
		if world_object_removals.has(String(key)):
			continue
		effective[String(key)] = (base_world_objects[key] as Dictionary).duplicate(true)
	for key in world_object_additions.keys():
		effective[String(key)] = (world_object_additions[key] as Dictionary).duplicate(true)
	return effective


func get_world_object_data(object_key: String) -> Dictionary:
	if world_object_additions.has(object_key):
		return (world_object_additions[object_key] as Dictionary).duplicate(true)
	if world_object_removals.has(object_key):
		return {}
	if base_world_objects.has(object_key):
		return (base_world_objects[object_key] as Dictionary).duplicate(true)
	return {}


func has_generated_world_object(object_key: String) -> bool:
	return base_world_objects.has(object_key)


func has_world_object(object_key: String) -> bool:
	return not get_world_object_data(object_key).is_empty()


func add_world_object_addition(local_origin: Vector2i, object_id: String) -> Dictionary:
	var object_key := build_world_object_key(object_id, local_origin)
	var data := {
		"object_id": object_id,
		"origin_x": local_origin.x,
		"origin_y": local_origin.y,
	}
	world_object_additions[object_key] = data
	world_object_removals.erase(object_key)
	return data.duplicate(true)


func remove_world_object(object_key: String) -> bool:
	if world_object_additions.has(object_key):
		world_object_additions.erase(object_key)
		return true
	if base_world_objects.has(object_key):
		world_object_removals[object_key] = true
		return true
	return false


func has_any_modifications() -> bool:
	return (
		not top_modifications.is_empty()
		or not ground_modifications.is_empty()
		or not world_object_additions.is_empty()
		or not world_object_removals.is_empty()
	)


func serialize() -> PackedByteArray:
	var data: Dictionary = {
		"cx": chunk_coord.x,
		"cy": chunk_coord.y,
		"ground": ground_base_tiles,
		"top": top_base_tiles,
		"base_world_objects": base_world_objects,
		"ground_mods": ground_modifications,
		"top_mods": top_modifications,
		"world_object_additions": world_object_additions,
		"world_object_removals": world_object_removals,
	}
	return var_to_bytes(data)


static func deserialize(bytes: PackedByteArray) -> ChunkData:
	var data: Dictionary = bytes_to_var(bytes)
	var chunk := ChunkData.new(Vector2i(data["cx"], data["cy"]))
	chunk.ground_base_tiles = data["ground"]
	chunk.top_base_tiles = data["top"]
	chunk.base_world_objects = data.get("base_world_objects", {})
	chunk.ground_modifications = data.get("ground_mods", {})
	chunk.top_modifications = data.get("top_mods", {})
	chunk.world_object_additions = data.get("world_object_additions", {})
	chunk.world_object_removals = data.get("world_object_removals", {})
	return chunk


static func build_world_object_key(object_id: String, local_origin: Vector2i) -> String:
	return "%s:%s:%s" % [object_id, local_origin.x, local_origin.y]


static func local_origin_from_data(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("origin_x", 0)), int(data.get("origin_y", 0)))
