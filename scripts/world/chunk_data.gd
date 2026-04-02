class_name ChunkData
extends Resource
## Data structure for a single 16x16 chunk of the world.
## Stores base terrain tiles and player modifications separately
## for compact serialization (only changes need saving).

## Chunk coordinate in chunk-space (not tile-space).
var chunk_coord: Vector2i

## Base terrain tiles generated from noise — flat array of 256 ints (16x16).
## Index = y * CHUNK_SIZE + x. Value = tile atlas index (-1 = empty).
var base_tiles: PackedInt32Array

## Player modifications on top of base terrain. Key = local tile index, Value = tile atlas index.
## -1 means the tile was removed (dug out).
var modifications: Dictionary = {}


func _init(coord: Vector2i = Vector2i.ZERO) -> void:
	chunk_coord = coord
	base_tiles = PackedInt32Array()
	base_tiles.resize(GameConstants.CHUNK_SIZE * GameConstants.CHUNK_SIZE)
	base_tiles.fill(-1)


## Returns the effective tile at a local position (modification overrides base).
func get_tile(local_x: int, local_y: int) -> int:
	var idx: int = local_y * GameConstants.CHUNK_SIZE + local_x
	if modifications.has(idx):
		return modifications[idx]
	return base_tiles[idx]


## Records a player modification at a local position.
func set_modification(local_x: int, local_y: int, tile_id: int) -> void:
	var idx: int = local_y * GameConstants.CHUNK_SIZE + local_x
	modifications[idx] = tile_id


## Serializes chunk data into a PackedByteArray for network transfer.
func serialize() -> PackedByteArray:
	var data: Dictionary = {
		"cx": chunk_coord.x,
		"cy": chunk_coord.y,
		"base": base_tiles,
		"mods": modifications,
	}
	return var_to_bytes(data)


## Creates a ChunkData from a PackedByteArray received over the network.
static func deserialize(bytes: PackedByteArray) -> ChunkData:
	var data: Dictionary = bytes_to_var(bytes)
	var chunk := ChunkData.new(Vector2i(data["cx"], data["cy"]))
	chunk.base_tiles = data["base"]
	chunk.modifications = data["mods"]
	return chunk
