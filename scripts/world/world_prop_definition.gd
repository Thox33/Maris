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
## Ground types this prop may be placed on (e.g. ["grass"], ["sand"]).
## Empty array means any solid ground is allowed.
var allowed_ground_names: Array[String]


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
	p_allowed_ground_names: Array[String] = [],
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
	allowed_ground_names = p_allowed_ground_names.duplicate()


## Returns true if the given ground name is valid for this prop.
## Empty allowed_ground_names means any solid ground is accepted.
func is_ground_allowed(ground_name: String) -> bool:
	if allowed_ground_names.is_empty():
		return true
	for allowed in allowed_ground_names:
		if ground_name.begins_with(allowed):
			return true
	return false


func get_world_position(cell: Vector2i) -> Vector2:
	return Vector2(
		cell.x * GameConstants.TILE_SIZE + anchor_offset_px.x,
		cell.y * GameConstants.TILE_SIZE + anchor_offset_px.y
	)


func get_sprite_offset() -> Vector2:
	return Vector2(-anchor_offset_px.x, -sprite_size_px.y)


func build_collision_rects() -> Array[Dictionary]:
	return collision_rects.duplicate(true)


func get_hit_cell_offsets() -> Array[Vector2i]:
	var rect := Rect2(Vector2(0.0, anchor_offset_px.y - sprite_size_px.y), sprite_size_px)
	var min_x := floori(rect.position.x / float(GameConstants.TILE_SIZE))
	var min_y := floori(rect.position.y / float(GameConstants.TILE_SIZE))
	var max_x := ceili((rect.position.x + rect.size.x) / float(GameConstants.TILE_SIZE)) - 1
	var max_y := ceili((rect.position.y + rect.size.y) / float(GameConstants.TILE_SIZE)) - 1

	var offsets: Array[Vector2i] = []
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			offsets.append(Vector2i(x, y))
	return offsets


func covers_hit_cell(foot_cell: Vector2i, hit_cell: Vector2i) -> bool:
	return hit_cell in get_hit_world_cells(foot_cell)


func get_hit_world_cells(foot_cell: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for offset in get_hit_cell_offsets():
		cells.append(foot_cell + offset)
	return cells
