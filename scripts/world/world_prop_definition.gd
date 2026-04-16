class_name WorldPropDefinition
extends RefCounted
## Immutable definition for a single-cell world prop anchored at its foot pivot.

const DEFAULT_ATLAS_PATH := "res://assets/tilesets/terrain_tiles.png"

var id: int
var name: String
var atlas_coord: Vector2i
var atlas_texture_path: String
var anchor_offset_px: Vector2
var sprite_size_px: Vector2
var collision_rects: Array[Dictionary]
var breakable: bool
var break_hardness: float
var move_speed_factor: float
var placement_variants: Array[int]
var drop_prop_id: int
var sway_enabled: bool
var sway_amount: float
var sway_speed: float
var rigid_base_px: float


func _init(
	p_id: int,
	p_name: String,
	p_atlas_coord: Vector2i,
	p_anchor_offset_px: Vector2 = Vector2(GameConstants.TILE_SIZE / 2.0, GameConstants.TILE_SIZE),
	p_sprite_size_px: Vector2 = Vector2(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE),
	p_collision_rects: Array[Dictionary] = [],
	p_breakable: bool = true,
	p_break_hardness: float = 1.0,
	p_move_speed_factor: float = 1.0,
	p_placement_variants: Array[int] = [],
	p_drop_prop_id: int = -1,
	p_sway_enabled: bool = false,
	p_sway_amount: float = 4.0,
	p_sway_speed: float = 3.0,
	p_rigid_base_px: float = 0.0,
	p_atlas_texture_path: String = DEFAULT_ATLAS_PATH,
) -> void:
	id = p_id
	name = p_name
	atlas_coord = p_atlas_coord
	anchor_offset_px = p_anchor_offset_px
	sprite_size_px = p_sprite_size_px
	collision_rects = p_collision_rects.duplicate(true)
	breakable = p_breakable
	break_hardness = maxf(p_break_hardness, 0.0)
	move_speed_factor = p_move_speed_factor
	placement_variants = p_placement_variants.duplicate()
	drop_prop_id = p_drop_prop_id if p_drop_prop_id >= 0 else p_id
	sway_enabled = p_sway_enabled
	sway_amount = maxf(p_sway_amount, 0.0)
	sway_speed = maxf(p_sway_speed, 0.0)
	rigid_base_px = maxf(p_rigid_base_px, 0.0)
	atlas_texture_path = p_atlas_texture_path


func get_world_position(cell: Vector2i) -> Vector2:
	return Vector2(
		cell.x * GameConstants.TILE_SIZE + anchor_offset_px.x,
		cell.y * GameConstants.TILE_SIZE + anchor_offset_px.y
	)


func get_sprite_offset() -> Vector2:
	return -anchor_offset_px


func build_collision_rects() -> Array[Dictionary]:
	return collision_rects.duplicate(true)
