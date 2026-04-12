class_name TileProperties
extends RefCounted
## Central registry of all tile types.
## Integer IDs are stable and permanent - never reuse a removed ID.
## String names are the canonical keys used in save files and code.

## Sentinel for empty / open-water cells.
const EMPTY: int = -1
const INVALID_ATLAS_COORD := Vector2i(-1, -1)

enum RenderKind {
	FLAT_BASE,
	SWAY_DECOR,
	BLOCK_OCCLUDER,
	TALL_STRUCTURE,
}

## Master registry: stable integer ID -> TileProperties.
## To add a tile: append a new entry with the next unused ID.
## Atlas layout: row 0 = terrain, row 1 = coral variants.
static var registry: Dictionary = {
	0: TileProperties.new(0, "sand", Vector2i(0, 0), true, 1.0, true, 0.8, -1, [], RenderKind.BLOCK_OCCLUDER),
	1: TileProperties.new(
		1,
		"stone",
		Vector2i(1, 0),
		true,
		1.0,
		true,
		2.0,
		-1,
		[],
		RenderKind.TALL_STRUCTURE,
		Vector2i(2, 0),
		Vector2i(3, 0),
		6
	),
	2: TileProperties.new(
		2,
		"coral",
		Vector2i(0, 1),
		false,
		0.4,
		true,
		0.4,
		-1,
		[2, 3, 4, 5, 6, 7],
		RenderKind.SWAY_DECOR
	),
	3: TileProperties.new(3, "coral_fan", Vector2i(1, 1), false, 0.4, true, 0.4, 2, [], RenderKind.SWAY_DECOR),
	4: TileProperties.new(4, "coral_kelp", Vector2i(2, 1), false, 0.4, true, 0.4, 2, [], RenderKind.SWAY_DECOR),
	5: TileProperties.new(5, "coral_brain", Vector2i(3, 1), false, 0.4, true, 0.4, 2, [], RenderKind.SWAY_DECOR),
	6: TileProperties.new(6, "coral_anemone", Vector2i(4, 1), false, 0.4, true, 0.4, 2, [], RenderKind.SWAY_DECOR),
	7: TileProperties.new(7, "coral_tube", Vector2i(5, 1), false, 0.4, true, 0.4, 2, [], RenderKind.SWAY_DECOR),
}

## Reverse lookup: string name -> integer ID. Keep in sync with registry.
static var by_name: Dictionary = {
	"sand": 0,
	"stone": 1,
	"coral": 2,
	"coral_fan": 3,
	"coral_kelp": 4,
	"coral_brain": 5,
	"coral_anemone": 6,
	"coral_tube": 7,
}

## All coral tile IDs for random selection during world generation.
static var coral_variants: Array[int] = [2, 3, 4, 5, 6, 7]

## Stable integer ID (never reuse a removed ID).
var id: int
## Canonical string key - used in save files and code.
var name: String
## Column/row in terrain_tileset.tres atlas source 0.
var atlas_coord: Vector2i
## Whether the tile blocks movement (has physics collision).
var solid: bool
## Multiplier applied to move speed when overlapping this tile.
var move_speed_factor: float
## Whether this tile can be broken by the player.
var breakable: bool
## Time in seconds to break this tile.
var hardness: float
## Which tile ID to use for item drop lookup. Defaults to own id.
## Coral variants all map to the base coral tile so they drop the same item.
var drop_tile_id: int
## Optional pool of tile IDs that may be chosen when this tile is placed.
## Use this for one gameplay tile with multiple visual variants.
var placement_variants: Array[int]
## How this tile should be rendered in the world.
var render_kind: RenderKind
## Atlas coord for the visible body/front face in the world.
var body_atlas_coord: Vector2i
## Atlas coord for the cap that overhangs above the block body.
var cap_atlas_coord: Vector2i
## How far the cap should protrude upward from the block cell.
var cap_offset_px: int


func _init(
	p_id: int,
	p_name: String,
	p_atlas_coord: Vector2i,
	p_solid: bool,
	p_move_speed_factor: float,
	p_breakable: bool,
	p_hardness: float,
	p_drop_tile_id: int = -1,
	p_placement_variants: Array[int] = [],
	p_render_kind: RenderKind = RenderKind.FLAT_BASE,
	p_body_atlas_coord: Vector2i = INVALID_ATLAS_COORD,
	p_cap_atlas_coord: Vector2i = INVALID_ATLAS_COORD,
	p_cap_offset_px: int = 0,
) -> void:
	id = p_id
	name = p_name
	atlas_coord = p_atlas_coord
	solid = p_solid
	move_speed_factor = p_move_speed_factor
	breakable = p_breakable
	hardness = p_hardness
	drop_tile_id = p_drop_tile_id if p_drop_tile_id >= 0 else p_id
	placement_variants = p_placement_variants.duplicate()
	render_kind = p_render_kind
	body_atlas_coord = p_body_atlas_coord if p_body_atlas_coord != INVALID_ATLAS_COORD else p_atlas_coord
	cap_atlas_coord = p_cap_atlas_coord
	cap_offset_px = maxi(p_cap_offset_px, 0)


## Returns properties for a tile ID, or null for empty / water tiles.
static func get_properties(tile_id: int) -> TileProperties:
	return registry.get(tile_id)


func uses_sway_decor_layer() -> bool:
	return render_kind == RenderKind.SWAY_DECOR


func uses_block_occluder_visual() -> bool:
	return render_kind == RenderKind.BLOCK_OCCLUDER


func uses_node_based_world_visual() -> bool:
	return uses_block_occluder_visual() or uses_tall_structure_visual()


func uses_tall_structure_visual() -> bool:
	return (
		render_kind == RenderKind.TALL_STRUCTURE
		and body_atlas_coord != INVALID_ATLAS_COORD
		and cap_atlas_coord != INVALID_ATLAS_COORD
	)


func build_world_visual_parts(tile_size_px: int) -> Array[Dictionary]:
	if uses_block_occluder_visual():
		return [
			{
				"atlas_coord": atlas_coord,
				"offset": Vector2(-tile_size_px / 2.0, -tile_size_px),
				"z_index": 0,
			}
		]

	if uses_tall_structure_visual():
		return [
			{
				"atlas_coord": body_atlas_coord,
				"offset": Vector2(-tile_size_px / 2.0, -tile_size_px),
				"z_index": 0,
			},
			{
				"atlas_coord": cap_atlas_coord,
				"offset": Vector2(-tile_size_px / 2.0, -tile_size_px - cap_offset_px),
				"z_index": 1,
			},
		]

	return []


## Returns the concrete tile ID that should be written when placing this tile.
## If the tile defines visual variants, one is chosen randomly.
static func resolve_placement_tile_id(tile_id: int) -> int:
	var props := get_properties(tile_id)
	if props == null:
		return tile_id
	if props.placement_variants.is_empty():
		return tile_id
	var variant_index: int = randi() % props.placement_variants.size()
	return props.placement_variants[variant_index]
