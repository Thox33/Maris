class_name ChunkData
extends Resource
const WORLD_PROP_CATALOG := preload("res://scripts/world/world_prop_catalog.gd")
## Data structure for a single 16x16 chunk of the world.
## Each cell holds two independent tile slots:
##   ground — the floor (GroundTileProperties ID, -1 = void/chasm)
##   top    — what sits on the floor (TileProperties ID, -1 = empty)
## Player modifications override base tiles per layer independently.
## Only modifications are saved to disk; base tiles are regenerated from noise.

## Chunk coordinate in chunk-space (not tile-space).
var chunk_coord: Vector2i

## Ground-layer base tiles — flat array of 256 ints (16x16).
## Index = y * CHUNK_SIZE + x. Value = GroundTileProperties ID (-1 = void).
var ground_base_tiles: PackedInt32Array

## Top-layer base tiles — flat array of 256 ints (16x16).
## Value = TileProperties ID (-1 = empty).
var top_base_tiles: PackedInt32Array

## Sparse base world props. Key = local tile index, Value = WorldPropCatalog ID.
var prop_base_cells: Dictionary = {}

## Player modifications to the ground layer. Key = local tile index, Value = GroundTileProperties ID.
var ground_modifications: Dictionary = {}

## Player modifications to the top layer. Key = local tile index, Value = TileProperties ID.
var top_modifications: Dictionary = {}

## Player modifications to the prop layer. Key = local tile index, Value = WorldPropCatalog ID.
var prop_modifications: Dictionary = {}


func _init(coord: Vector2i = Vector2i.ZERO) -> void:
	chunk_coord = coord
	var size: int = GameConstants.CHUNK_SIZE * GameConstants.CHUNK_SIZE
	ground_base_tiles = PackedInt32Array()
	ground_base_tiles.resize(size)
	ground_base_tiles.fill(-1)
	top_base_tiles = PackedInt32Array()
	top_base_tiles.resize(size)
	top_base_tiles.fill(-1)


## Returns the effective ground tile at a local position (modification overrides base).
func get_ground_tile(local_x: int, local_y: int) -> int:
	var idx: int = local_y * GameConstants.CHUNK_SIZE + local_x
	if ground_modifications.has(idx):
		return ground_modifications[idx]
	return ground_base_tiles[idx]


## Returns the effective top tile at a local position (modification overrides base).
func get_top_tile(local_x: int, local_y: int) -> int:
	var idx: int = local_y * GameConstants.CHUNK_SIZE + local_x
	if top_modifications.has(idx):
		return top_modifications[idx]
	return top_base_tiles[idx]


## Returns the effective world prop at a local position (modification overrides base).
func get_prop(local_x: int, local_y: int) -> int:
	var idx: int = local_y * GameConstants.CHUNK_SIZE + local_x
	if prop_modifications.has(idx):
		return prop_modifications[idx]
	return int(prop_base_cells.get(idx, WORLD_PROP_CATALOG.EMPTY))


## Records a player modification to the top layer at a local position.
func set_top_modification(local_x: int, local_y: int, tile_id: int) -> void:
	var idx: int = local_y * GameConstants.CHUNK_SIZE + local_x
	top_modifications[idx] = tile_id


## Records a player modification to the prop layer at a local position.
func set_prop_modification(local_x: int, local_y: int, prop_id: int) -> void:
	var idx: int = local_y * GameConstants.CHUNK_SIZE + local_x
	prop_modifications[idx] = prop_id


## Records a player modification to the ground layer at a local position.
func set_ground_modification(local_x: int, local_y: int, ground_id: int) -> void:
	var idx: int = local_y * GameConstants.CHUNK_SIZE + local_x
	ground_modifications[idx] = ground_id


## Returns true if either layer has player modifications.
func has_any_modifications() -> bool:
	return (
		not top_modifications.is_empty()
		or not ground_modifications.is_empty()
		or not prop_modifications.is_empty()
	)


## Serializes chunk data into a PackedByteArray for network transfer.
func serialize() -> PackedByteArray:
	var data: Dictionary = {
		"cx": chunk_coord.x,
		"cy": chunk_coord.y,
		"ground": ground_base_tiles,
		"top": top_base_tiles,
		"props": prop_base_cells,
		"ground_mods": ground_modifications,
		"top_mods": top_modifications,
		"prop_mods": prop_modifications,
	}
	return var_to_bytes(data)


## Creates a ChunkData from a PackedByteArray received over the network.
static func deserialize(bytes: PackedByteArray) -> ChunkData:
	var data: Dictionary = bytes_to_var(bytes)
	var chunk := ChunkData.new(Vector2i(data["cx"], data["cy"]))
	chunk.ground_base_tiles = data["ground"]
	chunk.top_base_tiles = data["top"]
	chunk.prop_base_cells = data.get("props", {})
	chunk.ground_modifications = data.get("ground_mods", {})
	chunk.top_modifications = data.get("top_mods", {})
	chunk.prop_modifications = data.get("prop_mods", {})
	return chunk
