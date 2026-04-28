class_name GroundTileProperties
extends RefCounted
## Central registry of all ground-layer tile types.
## Ground tiles form the base surface of every cell in the world.
## Integer IDs are stable and permanent — never reuse a removed ID.
##
## Sprites live in res://assets/tilesets/ground_tiles.png.
## To add a ground tile: append one entry in registry + one in by_name.

## Sentinel for void / chasm cells (impassable, no ground).
const EMPTY: int = -1

## Master registry: stable integer ID -> GroundTileProperties.
## Solid tiles — atlas: res://assets/tilesets/ground_tiles.png, cols 0-11, row 0.
##   0-2  dirt variants
##   3-5  sand variants
##   6-8  stone variants
##   9-11 grass variants
## Liquid tiles — atlas: res://assets/tilesets/liquid_tiles.png, cols 0-1, row 0.
##   12   water
##   13   lava
static var registry: Dictionary = {
	0:  GroundTileProperties.new(0,  "dirt",    Vector2i(0,  0), true,  false),
	1:  GroundTileProperties.new(1,  "dirt_b",  Vector2i(1,  0), true,  false),
	2:  GroundTileProperties.new(2,  "dirt_c",  Vector2i(2,  0), true,  false),
	3:  GroundTileProperties.new(3,  "sand",    Vector2i(3,  0), true,  false),
	4:  GroundTileProperties.new(4,  "sand_b",  Vector2i(4,  0), true,  false),
	5:  GroundTileProperties.new(5,  "sand_c",  Vector2i(5,  0), true,  false),
	6:  GroundTileProperties.new(6,  "stone",   Vector2i(6,  0), true,  false),
	7:  GroundTileProperties.new(7,  "stone_b", Vector2i(7,  0), true,  false),
	8:  GroundTileProperties.new(8,  "stone_c", Vector2i(8,  0), true,  false),
	9:  GroundTileProperties.new(9,  "grass",   Vector2i(9,  0), true,  false),
	10: GroundTileProperties.new(10, "grass_b", Vector2i(10, 0), true,  false),
	11: GroundTileProperties.new(11, "grass_c", Vector2i(11, 0), true,  false),
	12: GroundTileProperties.new(12, "water",   Vector2i(0,  0), false, true),
	13: GroundTileProperties.new(13, "lava",    Vector2i(1,  0), false, true),
}

## Reverse lookup: string name -> integer ID. Keep in sync with registry.
static var by_name: Dictionary = {
	"dirt":    0,  "dirt_b":  1,  "dirt_c":  2,
	"sand":    3,  "sand_b":  4,  "sand_c":  5,
	"stone":   6,  "stone_b": 7,  "stone_c": 8,
	"grass":   9,  "grass_b": 10, "grass_c": 11,
	"water":   12, "lava":    13,
}

## Variant groups: base name -> list of IDs. Use for world generation.
static var variants: Dictionary = {
	"dirt":  [0, 1, 2],
	"sand":  [3, 4, 5],
	"stone": [6, 7, 8],
	"grass": [9, 10, 11],
}

## Stable integer ID (never reuse a removed ID).
var id: int
## Canonical string key — used in save files and code.
var name: String
## Column/row in ground_tiles.png (source 0 of the runtime-built ground TileSet).
var atlas_coord: Vector2i
## True if the player can walk on this tile.
var is_solid: bool
## True if this is a liquid tile (water, lava). Impassable with special effects.
var is_liquid: bool


func _init(
	p_id: int,
	p_name: String,
	p_atlas_coord: Vector2i,
	p_solid: bool,
	p_liquid: bool,
) -> void:
	id = p_id
	name = p_name
	atlas_coord = p_atlas_coord
	is_solid = p_solid
	is_liquid = p_liquid


## Returns properties for a ground tile ID, or null for void cells.
static func get_properties(ground_id: int) -> GroundTileProperties:
	return registry.get(ground_id)


## Returns true if the player can walk on this tile.
func is_passable() -> bool:
	return is_solid and not is_liquid
