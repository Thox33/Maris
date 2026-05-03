class_name WorldObjectDefinition
extends RefCounted

const DEFAULT_ATLAS_PATH := "res://assets/tilesets/terrain_tiles.png"

const KIND_PROP := "prop"
const KIND_STRUCTURE := "structure"

var id: String
var kind: String
var cells: Array[Dictionary]
var atlas_texture_path: String
var anchor_offset_px: Vector2
var placement_anchor_cell: Vector2i
var break_hardness: float
var move_speed_factor: float
var placement_variants: Array[String]
var drop_object_id: String
var sway_enabled: bool
var sway_amount: float
var sway_speed: float
var rigid_base_px: float
var allowed_ground_names: Array[String]
var legacy_prop_id: int
var legacy_structure_id: String

var occupied_cells: Array[Vector2i]
var collision_cells: Array[Vector2i]
var breakable_cells: Array[Vector2i]
var hit_cells: Array[Vector2i]


func _init(
	p_id: String,
	p_kind: String,
	p_cells: Array[Dictionary],
	p_anchor_offset_px: Vector2,
	p_placement_anchor_cell: Vector2i = Vector2i.ZERO,
	p_atlas_texture_path: String = DEFAULT_ATLAS_PATH,
	p_break_hardness: float = 1.0,
	p_move_speed_factor: float = 1.0,
	p_placement_variants: Array[String] = [],
	p_drop_object_id: String = "",
	p_sway_enabled: bool = false,
	p_sway_amount: float = 4.0,
	p_sway_speed: float = 3.0,
	p_rigid_base_px: float = 0.0,
	p_allowed_ground_names: Array[String] = [],
	p_legacy_prop_id: int = -1,
	p_legacy_structure_id: String = "",
) -> void:
	id = p_id
	kind = p_kind
	cells = []
	for cell_data in p_cells:
		cells.append(cell_data.duplicate(true))
	anchor_offset_px = p_anchor_offset_px
	placement_anchor_cell = p_placement_anchor_cell
	atlas_texture_path = p_atlas_texture_path
	break_hardness = maxf(p_break_hardness, 0.0)
	move_speed_factor = maxf(p_move_speed_factor, 0.0)
	placement_variants = p_placement_variants.duplicate()
	drop_object_id = p_drop_object_id if not p_drop_object_id.is_empty() else p_id
	sway_enabled = p_sway_enabled
	sway_amount = maxf(p_sway_amount, 0.0)
	sway_speed = maxf(p_sway_speed, 0.0)
	rigid_base_px = maxf(p_rigid_base_px, 0.0)
	allowed_ground_names = p_allowed_ground_names.duplicate()
	legacy_prop_id = p_legacy_prop_id
	legacy_structure_id = p_legacy_structure_id
	occupied_cells = _collect_cells_with_flag("occupied")
	collision_cells = _collect_collision_cells()
	breakable_cells = _collect_breakable_cells()
	hit_cells = _collect_hit_cells()


func is_ground_allowed(ground_name: String) -> bool:
	if allowed_ground_names.is_empty():
		return true
	for allowed in allowed_ground_names:
		if ground_name.begins_with(allowed):
			return true
	return false


func get_origin_cell(data: Dictionary) -> Vector2i:
	return Vector2i(int(data.get("origin_x", 0)), int(data.get("origin_y", 0)))


func get_origin_from_placement_cell(target_cell: Vector2i) -> Vector2i:
	return target_cell - placement_anchor_cell


func get_world_position(origin: Vector2i) -> Vector2:
	return Vector2(
		origin.x * GameConstants.TILE_SIZE + anchor_offset_px.x,
		origin.y * GameConstants.TILE_SIZE + anchor_offset_px.y
	)


func build_visual_parts() -> Array[Dictionary]:
	var parts: Array[Dictionary] = []
	for cell_data in cells:
		var local_cell := cell_data.get("cell", Vector2i.ZERO) as Vector2i
		var visual_parts: Array = cell_data.get("visual_parts", [])
		if visual_parts.is_empty():
			var atlas_coord := cell_data.get("atlas_coord", Vector2i(-1, -1)) as Vector2i
			if atlas_coord.x >= 0 and atlas_coord.y >= 0:
				parts.append(
					{
						"atlas_coord": atlas_coord,
						"offset": _build_cell_top_left_offset(local_cell, GameConstants.TILE_SIZE),
						"size_px": Vector2(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE),
						"z_index": int(cell_data.get("z_index", 0)),
					}
				)
			continue

		for part_variant in visual_parts:
			if not (part_variant is Dictionary):
				continue
			var part := part_variant as Dictionary
			parts.append(
				{
					"atlas_coord": part.get("atlas_coord", Vector2i.ZERO) as Vector2i,
					"offset": part.get("offset", Vector2.ZERO) as Vector2,
					"size_px": part.get(
						"size_px",
						Vector2(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE)
					) as Vector2,
					"z_index": int(part.get("z_index", cell_data.get("z_index", 0))),
				}
			)
	return parts


func build_collision_rects(tile_size_px: int = GameConstants.TILE_SIZE) -> Array[Dictionary]:
	var rects: Array[Dictionary] = []
	for cell_data in cells:
		var local_cell := cell_data.get("cell", Vector2i.ZERO) as Vector2i
		var custom_rects: Array = cell_data.get("collision_rects", [])
		var has_custom_rects := not custom_rects.is_empty()
		var collides := bool(cell_data.get("collides", false)) or has_custom_rects
		if not collides:
			continue
		var cell_top_left := _build_cell_top_left_offset(local_cell, tile_size_px)
		if not has_custom_rects:
			rects.append(
				{
					"size": Vector2(tile_size_px, tile_size_px),
					"offset": cell_top_left + Vector2(tile_size_px / 2.0, tile_size_px / 2.0),
				}
			)
			continue
		for custom_rect_variant in custom_rects:
			if not (custom_rect_variant is Dictionary):
				continue
			var custom_rect := custom_rect_variant as Dictionary
			var rect_size := custom_rect.get("size", Vector2(tile_size_px, tile_size_px)) as Vector2
			var rect_offset := custom_rect.get("offset", Vector2.ZERO) as Vector2
			rects.append(
				{
					"size": rect_size,
					"offset": cell_top_left + rect_offset + rect_size / 2.0,
				}
			)
	return rects


func get_occupied_world_cells(origin: Vector2i) -> Array[Vector2i]:
	return _translate_cells(origin, occupied_cells)


func get_breakable_world_cells(origin: Vector2i) -> Array[Vector2i]:
	return _translate_cells(origin, breakable_cells)


func get_collision_world_cells(origin: Vector2i) -> Array[Vector2i]:
	return _translate_cells(origin, collision_cells)


func get_hit_world_cells(origin: Vector2i) -> Array[Vector2i]:
	return _translate_cells(origin, hit_cells)


func covers_hit_cell(origin: Vector2i, hit_cell: Vector2i) -> bool:
	return hit_cell in get_hit_world_cells(origin)


func get_break_world_position(origin: Vector2i) -> Vector2:
	var relevant_cells := get_breakable_world_cells(origin)
	if relevant_cells.is_empty():
		relevant_cells = get_hit_world_cells(origin)
	if relevant_cells.is_empty():
		relevant_cells = [origin]

	var sum := Vector2.ZERO
	for cell in relevant_cells:
		sum += Vector2(
			cell.x * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0,
			cell.y * GameConstants.TILE_SIZE + GameConstants.TILE_SIZE / 2.0
		)
	return sum / float(relevant_cells.size())


func _translate_cells(origin: Vector2i, source_cells: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in source_cells:
		result.append(origin + cell)
	return result


func _collect_cells_with_flag(flag_name: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell_data in cells:
		if not bool(cell_data.get(flag_name, false)):
			continue
		result.append(cell_data.get("cell", Vector2i.ZERO) as Vector2i)
	return result


func _collect_collision_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell_data in cells:
		var custom_rects: Array = cell_data.get("collision_rects", [])
		if bool(cell_data.get("collides", false)) or not custom_rects.is_empty():
			result.append(cell_data.get("cell", Vector2i.ZERO) as Vector2i)
	return result


func _collect_breakable_cells() -> Array[Vector2i]:
	var result := _collect_cells_with_flag("breakable")
	if not result.is_empty():
		return result
	return _collect_hit_cells()


func _collect_hit_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell_data in cells:
		var has_visual := false
		var visual_parts: Array = cell_data.get("visual_parts", [])
		if not visual_parts.is_empty():
			has_visual = true
		else:
			var atlas_coord := cell_data.get("atlas_coord", Vector2i(-1, -1)) as Vector2i
			has_visual = atlas_coord.x >= 0 and atlas_coord.y >= 0
		if (
			bool(cell_data.get("hit", false))
			or bool(cell_data.get("breakable", false))
			or bool(cell_data.get("occupied", false))
			or has_visual
		):
			result.append(cell_data.get("cell", Vector2i.ZERO) as Vector2i)
	return result


func _build_cell_top_left_offset(local_cell: Vector2i, tile_size_px: int) -> Vector2:
	return Vector2(
		local_cell.x * tile_size_px - anchor_offset_px.x,
		local_cell.y * tile_size_px - anchor_offset_px.y
	)
