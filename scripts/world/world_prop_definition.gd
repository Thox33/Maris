class_name WorldPropDefinition
extends "res://scripts/world/world_object_definition.gd"

var name: String
var atlas_coord: Vector2i
var sprite_size_px: Vector2
var collision_rects: Array[Dictionary]
var breakable: bool
var drop_prop_id: int


func _init(
	p_id: int,
	p_name: String,
	p_atlas_coord: Vector2i,
	p_anchor_offset_px: Vector2 = Vector2(GameConstants.TILE_SIZE / 2.0, GameConstants.TILE_SIZE),
	p_sprite_size_px: Vector2 = Vector2(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE),
	p_collision_rects: Array = [],
	p_breakable: bool = true,
	p_break_hardness: float = 1.0,
	p_move_speed_factor: float = 1.0,
	p_placement_variants: Array = [],
	p_drop_prop_id: int = -1,
	p_sway_enabled: bool = false,
	p_sway_amount: float = 4.0,
	p_sway_speed: float = 3.0,
	p_rigid_base_px: float = 0.0,
	p_atlas_texture_path: String = DEFAULT_ATLAS_PATH,
	p_allowed_ground_names: Array[String] = [],
) -> void:
	name = p_name
	atlas_coord = p_atlas_coord
	sprite_size_px = p_sprite_size_px
	collision_rects = []
	for rect_variant in p_collision_rects:
		if not (rect_variant is Dictionary):
			continue
		collision_rects.append((rect_variant as Dictionary).duplicate(true))
	breakable = p_breakable
	drop_prop_id = p_drop_prop_id if p_drop_prop_id >= 0 else p_id

	var resolved_placement_variants: Array[String] = []
	for variant in p_placement_variants:
		resolved_placement_variants.append(String(variant))

	super._init(
		p_name,
		KIND_PROP,
		_build_cells(
			p_atlas_coord,
			p_anchor_offset_px,
			p_sprite_size_px,
			p_collision_rects,
			p_breakable
		),
		p_anchor_offset_px,
		Vector2i.ZERO,
		p_atlas_texture_path,
		p_break_hardness,
		p_move_speed_factor,
		resolved_placement_variants,
		p_name,
		p_sway_enabled,
		p_sway_amount,
		p_sway_speed,
		p_rigid_base_px,
		p_allowed_ground_names,
		p_id,
		""
	)


func build_collision_rects(_tile_size_px: int = GameConstants.TILE_SIZE) -> Array[Dictionary]:
	var rects: Array[Dictionary] = []
	for rect in collision_rects:
		rects.append(rect.duplicate(true))
	return rects


func get_sprite_offset() -> Vector2:
	return Vector2(-anchor_offset_px.x, -sprite_size_px.y)


func get_hit_cell_offsets() -> Array[Vector2i]:
	return hit_cells.duplicate()


static func _build_cells(
	p_atlas_coord: Vector2i,
	p_anchor_offset_px: Vector2,
	p_sprite_size_px: Vector2,
	p_collision_rects: Array,
	p_breakable: bool
) -> Array[Dictionary]:
	var cells_by_key: Dictionary = {}
	var sprite_rect := Rect2(
		Vector2(0.0, p_anchor_offset_px.y - p_sprite_size_px.y),
		p_sprite_size_px
	)
	var min_x := floori(sprite_rect.position.x / float(GameConstants.TILE_SIZE))
	var min_y := floori(sprite_rect.position.y / float(GameConstants.TILE_SIZE))
	var max_x := ceili((sprite_rect.position.x + sprite_rect.size.x) / float(GameConstants.TILE_SIZE)) - 1
	var max_y := ceili((sprite_rect.position.y + sprite_rect.size.y) / float(GameConstants.TILE_SIZE)) - 1

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var cell := Vector2i(x, y)
			cells_by_key[_cell_key(cell)] = {
				"cell": cell,
				"hit": true,
				"breakable": p_breakable,
			}

	var origin_key := _cell_key(Vector2i.ZERO)
	if not cells_by_key.has(origin_key):
		cells_by_key[origin_key] = {
			"cell": Vector2i.ZERO,
			"hit": true,
			"breakable": p_breakable,
		}

	var origin_cell := cells_by_key[origin_key] as Dictionary
	origin_cell["occupied"] = true
	origin_cell["collides"] = not p_collision_rects.is_empty()
	origin_cell["collision_rects"] = p_collision_rects.duplicate(true)
	origin_cell["visual_parts"] = [
		{
			"atlas_coord": p_atlas_coord,
			"offset": Vector2(-p_anchor_offset_px.x, -p_sprite_size_px.y),
			"size_px": p_sprite_size_px,
			"z_index": 0,
		}
	]
	cells_by_key[origin_key] = origin_cell

	var result: Array[Dictionary] = []
	for cell_key in cells_by_key.keys():
		result.append((cells_by_key[cell_key] as Dictionary).duplicate(true))
	return result


static func _cell_key(cell: Vector2i) -> String:
	return "%s:%s" % [cell.x, cell.y]
