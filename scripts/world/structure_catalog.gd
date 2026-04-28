class_name StructureCatalog
extends RefCounted
## Static registry of multi-tile structures.

const STRUCTURE_ATLAS_PATH := "res://assets/tilesets/structure_tiles.png"

static var registry: Dictionary = _build_registry()


static func get_definition(structure_id: String) -> StructureDefinition:
	return registry.get(structure_id)


static func _build_registry() -> Dictionary:
	return {
		"large_furnace": _build_large_furnace_definition(),
		"botanical_table": _build_botanical_table_definition(),
	}


static func _build_large_furnace_definition() -> StructureDefinition:
	var footprint := Vector2i(2, 3)
	var anchor := _build_south_center_anchor(footprint)
	var base_cells: Array[Vector2i] = [
		Vector2i(0, 2),
		Vector2i(1, 2),
		Vector2i(0, 1),
		Vector2i(1, 1),
	]
	var parts: Array[Dictionary] = [
		{
			"atlas_coord": Vector2i(0, 0),
			"offset": _cell_top_left_offset(anchor, Vector2i(0, 0)),
			"z_index": 1,
		},
		{
			"atlas_coord": Vector2i(1, 0),
			"offset": _cell_top_left_offset(anchor, Vector2i(1, 0)),
			"z_index": 1,
		},
		{
			"atlas_coord": Vector2i(0, 1),
			"offset": _cell_top_left_offset(anchor, Vector2i(0, 1)),
			"z_index": 0,
		},
		{
			"atlas_coord": Vector2i(1, 1),
			"offset": _cell_top_left_offset(anchor, Vector2i(1, 1)),
			"z_index": 0,
		},
		{
			"atlas_coord": Vector2i(0, 2),
			"offset": _cell_top_left_offset(anchor, Vector2i(0, 2)),
			"z_index": 0,
		},
		{
			"atlas_coord": Vector2i(1, 2),
			"offset": _cell_top_left_offset(anchor, Vector2i(1, 2)),
			"z_index": 0,
		},
	]

	return StructureDefinition.new(
		"large_furnace",
		footprint,
		base_cells,
		base_cells,
		base_cells,
		parts,
		anchor,
		Vector2i(0, 2),
		STRUCTURE_ATLAS_PATH,
		3.0
	)


static func _build_botanical_table_definition() -> StructureDefinition:
	var footprint := Vector2i(3, 2)
	var anchor := _build_south_center_anchor(footprint)
	var occupied_cells := _build_rect_cells(footprint.x, footprint.y)
	var collision_cells: Array[Vector2i] = [
		Vector2i(0, 1),
		Vector2i(1, 1),
		Vector2i(2, 1),
	]
	var parts: Array[Dictionary] = [
		{
			"atlas_coord": Vector2i(0, 3),
			"offset": _cell_top_left_offset(anchor, Vector2i(0, 0)),
			"z_index": 1,
		},
		{
			"atlas_coord": Vector2i(1, 3),
			"offset": _cell_top_left_offset(anchor, Vector2i(1, 0)),
			"z_index": 1,
		},
		{
			"atlas_coord": Vector2i(2, 3),
			"offset": _cell_top_left_offset(anchor, Vector2i(2, 0)),
			"z_index": 1,
		},
		{
			"atlas_coord": Vector2i(0, 4),
			"offset": _cell_top_left_offset(anchor, Vector2i(0, 1)),
			"z_index": 0,
		},
		{
			"atlas_coord": Vector2i(1, 4),
			"offset": _cell_top_left_offset(anchor, Vector2i(1, 1)),
			"z_index": 0,
		},
		{
			"atlas_coord": Vector2i(2, 4),
			"offset": _cell_top_left_offset(anchor, Vector2i(2, 1)),
			"z_index": 0,
		},
	]

	return StructureDefinition.new(
		"botanical_table",
		footprint,
		occupied_cells,
		collision_cells,
		occupied_cells,
		parts,
		anchor,
		Vector2i(1, 1),
		STRUCTURE_ATLAS_PATH,
		2.0
	)


static func _build_rect_cells(width: int, height: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			cells.append(Vector2i(x, y))
	return cells


static func _build_south_center_anchor(footprint: Vector2i) -> Vector2:
	return Vector2(
		float(footprint.x * GameConstants.TILE_SIZE) / 2.0,
		float(footprint.y * GameConstants.TILE_SIZE)
	)


static func _cell_top_left_offset(anchor: Vector2, local_cell: Vector2i) -> Vector2:
	return Vector2(
		local_cell.x * GameConstants.TILE_SIZE - anchor.x,
		local_cell.y * GameConstants.TILE_SIZE - anchor.y
	)
