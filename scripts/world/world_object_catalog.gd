class_name WorldObjectCatalog
extends RefCounted

var _world_prop_definition_script = load("res://scripts/world/world_prop_definition.gd")
var _structure_definition_script = load("res://scripts/world/structure_definition.gd")

const EMPTY_ID := ""
const STRUCTURE_ATLAS_PATH := "res://assets/tilesets/structure_tiles.png"
const TREE_ATLAS_PATH := "res://assets/tilesets/tree_props.png"
const TREE_HEIGHT_PX: float = 32.0

var registry: Dictionary = _build_registry()
var by_legacy_prop_id: Dictionary = _build_by_legacy_prop_id()
var by_legacy_structure_id: Dictionary = _build_by_legacy_structure_id()
var coral_variants: Array[String] = _build_coral_variants()
var tree_variants: Array[String] = _build_tree_variants()


func get_definition(object_id: String):
	return registry.get(object_id)


func get_definition_by_prop_id(prop_id: int):
	var object_id: String = String(by_legacy_prop_id.get(prop_id, EMPTY_ID))
	if object_id.is_empty():
		return null
	return get_definition(object_id)


func get_definition_by_structure_id(structure_id: String):
	var object_id: String = String(by_legacy_structure_id.get(structure_id, EMPTY_ID))
	if object_id.is_empty():
		return null
	return get_definition(object_id)


func resolve_placement_object_id(object_id: String) -> String:
	var definition = get_definition(object_id)
	if definition == null:
		return object_id
	if definition.placement_variants.is_empty():
		return object_id
	var variant_index: int = randi() % definition.placement_variants.size()
	return definition.placement_variants[variant_index]


func get_hit_offset_bounds_for_props() -> Dictionary:
	var min_x := 0
	var max_x := 0
	var min_y := 0
	var max_y := 0

	for object_id in registry.keys():
		var definition = registry[object_id]
		if definition == null or String(definition.kind) != "prop":
			continue
		for offset in definition.hit_cells:
			min_x = mini(min_x, offset.x)
			max_x = maxi(max_x, offset.x)
			min_y = mini(min_y, offset.y)
			max_y = maxi(max_y, offset.y)

	return {
		"min_x": min_x,
		"max_x": max_x,
		"min_y": min_y,
		"max_y": max_y,
	}


func _build_registry() -> Dictionary:
	return {
		"coral": _build_coral_definition(0, "coral", Vector2i(0, 1), ["coral", "coral_fan", "coral_kelp", "coral_brain", "coral_anemone", "coral_tube"]),
		"coral_fan": _build_coral_definition(1, "coral_fan", Vector2i(1, 1)),
		"coral_kelp": _build_coral_definition(2, "coral_kelp", Vector2i(2, 1)),
		"coral_brain": _build_coral_definition(3, "coral_brain", Vector2i(3, 1)),
		"coral_anemone": _build_coral_definition(4, "coral_anemone", Vector2i(4, 1)),
		"coral_tube": _build_coral_definition(5, "coral_tube", Vector2i(5, 1)),
		"tree": _build_wide_tree_definition(6, "tree", Vector2i(0, 0), ["tree", "tree_b"]),
		"tree_b": _build_tree_definition(7, "tree_b", Vector2i(2, 0)),
		"large_furnace": _build_large_furnace_definition(),
		"botanical_table": _build_botanical_table_definition(),
		"anvil": _build_anvil_definition(),
		"work_bench": _build_work_bench_definition(),
	}


func _build_by_legacy_prop_id() -> Dictionary:
	var result: Dictionary = {}
	for object_id in registry.keys():
		var definition = registry[object_id]
		if definition != null and definition.legacy_prop_id >= 0:
			result[definition.legacy_prop_id] = definition.id
	return result


func _build_by_legacy_structure_id() -> Dictionary:
	var result: Dictionary = {}
	for object_id in registry.keys():
		var definition = registry[object_id]
		if definition != null and not definition.legacy_structure_id.is_empty():
			result[definition.legacy_structure_id] = definition.id
	return result


func _build_coral_variants() -> Array[String]:
	return ["coral", "coral_fan", "coral_kelp", "coral_brain", "coral_anemone", "coral_tube"]


func _build_tree_variants() -> Array[String]:
	return ["tree", "tree_b"]


func _build_coral_definition(
	prop_id: int,
	prop_name: String,
	atlas_coord: Vector2i,
	placement_variants: Array[String] = [],
):
	return _world_prop_definition_script.new(
		prop_id,
		prop_name,
		atlas_coord,
		Vector2(GameConstants.TILE_SIZE / 2.0, GameConstants.TILE_SIZE),
		Vector2(GameConstants.TILE_SIZE, GameConstants.TILE_SIZE),
		[],
		true,
		0.4,
		0.4,
		placement_variants,
		0,
		true,
		4.0,
		3.0,
		2.0
	)


func _build_wide_tree_definition(
	prop_id: int,
	prop_name: String,
	atlas_coord: Vector2i,
	placement_variants: Array[String] = [],
) -> Variant:
	var ts := float(GameConstants.TILE_SIZE)
	return _world_prop_definition_script.new(
		prop_id,
		prop_name,
		atlas_coord,
		Vector2(ts, ts),
		Vector2(ts * 2.0, TREE_HEIGHT_PX),
		[{"size": Vector2(12, 6), "offset": Vector2(0, -3)}],
		true,
		1.0,
		0.8,
		placement_variants,
		6,
		true,
		2.5,
		2.0,
		14.0,
		TREE_ATLAS_PATH,
		["grass"] as Array[String],
	)


func _build_tree_definition(
	prop_id: int,
	prop_name: String,
	atlas_coord: Vector2i,
	placement_variants: Array[String] = [],
) -> Variant:
	var ts := float(GameConstants.TILE_SIZE)
	return _world_prop_definition_script.new(
		prop_id,
		prop_name,
		atlas_coord,
		Vector2(ts / 2.0, ts),
		Vector2(ts, TREE_HEIGHT_PX),
		[{"size": Vector2(6, 6), "offset": Vector2(0, -3)}],
		true,
		1.0,
		0.8,
		placement_variants,
		6,
		true,
		2.5,
		2.0,
		14.0,
		TREE_ATLAS_PATH,
		["grass"] as Array[String],
	)


func _build_large_furnace_definition():
	var footprint: Vector2i = Vector2i(2, 3)
	var anchor: Vector2 = _build_south_center_anchor(footprint)
	var cells: Array[Dictionary] = [
		_cell(Vector2i(0, 0), Vector2i(0, 0), 1, false, false, true),
		_cell(Vector2i(1, 0), Vector2i(1, 0), 1, false, false, true),
		_cell(Vector2i(0, 1), Vector2i(0, 1), 0, true, true, true),
		_cell(Vector2i(1, 1), Vector2i(1, 1), 0, true, true, true),
		_cell(Vector2i(0, 2), Vector2i(0, 2), 0, true, true, true),
		_cell(Vector2i(1, 2), Vector2i(1, 2), 0, true, true, true),
	]

	return _structure_definition_script.new(
		"large_furnace",
		footprint,
		cells,
		anchor,
		Vector2i(0, 2),
		STRUCTURE_ATLAS_PATH,
		3.0
	)


func _build_botanical_table_definition():
	var footprint: Vector2i = Vector2i(3, 2)
	var anchor: Vector2 = _build_south_center_anchor(footprint)
	var cells: Array[Dictionary] = [
		_cell(Vector2i(0, 0), Vector2i(0, 3), 1, false, false, true),
		_cell(Vector2i(1, 0), Vector2i(1, 3), 1, false, false, true),
		_cell(Vector2i(2, 0), Vector2i(2, 3), 1, false, false, true),
		_cell(Vector2i(0, 1), Vector2i(0, 4), 0, true, true, true),
		_cell(Vector2i(1, 1), Vector2i(1, 4), 0, true, true, true),
		_cell(Vector2i(2, 1), Vector2i(2, 4), 0, true, true, true),
	]

	return _structure_definition_script.new(
		"botanical_table",
		footprint,
		cells,
		anchor,
		Vector2i(1, 1),
		STRUCTURE_ATLAS_PATH,
		2.0
	)


func _build_anvil_definition():
	var footprint: Vector2i = Vector2i(3, 2)
	var anchor: Vector2 = _build_south_center_anchor(footprint)
	var cells: Array[Dictionary] = [
		_cell(Vector2i(0, 0), Vector2i(0, 5), 1, false, false, true),
		_cell(Vector2i(1, 0), Vector2i(1, 5), 1, false, false, true),
		_cell(Vector2i(2, 0), Vector2i(2, 5), 1, false, false, true),
		_cell(Vector2i(0, 1), Vector2i(0, 6), 0, true, true, true),
		_cell(Vector2i(1, 1), Vector2i(1, 6), 0, true, true, true),
		_cell(Vector2i(2, 1), Vector2i(2, 6), 0, true, true, true),
	]

	return _structure_definition_script.new(
		"anvil",
		footprint,
		cells,
		anchor,
		Vector2i(1, 1),
		STRUCTURE_ATLAS_PATH,
		2.0
	)


func _build_work_bench_definition():
	var footprint: Vector2i = Vector2i(3, 2)
	var anchor: Vector2 = _build_south_center_anchor(footprint)
	var cells: Array[Dictionary] = [
		_cell(Vector2i(0, 0), Vector2i(0, 7), 1, false, false, true),
		_cell(Vector2i(1, 0), Vector2i(1, 7), 1, false, false, true),
		_cell(Vector2i(2, 0), Vector2i(2, 7), 1, false, false, true),
		_cell(Vector2i(0, 1), Vector2i(0, 8), 0, true, true, true),
		_cell(Vector2i(1, 1), Vector2i(1, 8), 0, true, true, true),
		_cell(Vector2i(2, 1), Vector2i(2, 8), 0, true, true, true),
	]

	return _structure_definition_script.new(
		"work_bench",
		footprint,
		cells,
		anchor,
		Vector2i(1, 1),
		STRUCTURE_ATLAS_PATH,
		2.0
	)


func _cell(
	local_cell: Vector2i,
	atlas_coord: Vector2i,
	z_index: int,
	occupied: bool = false,
	collides: bool = false,
	breakable: bool = true,
	collision_rects: Array[Dictionary] = []
) -> Dictionary:
	return {
		"cell": local_cell,
		"atlas_coord": atlas_coord,
		"z_index": z_index,
		"occupied": occupied,
		"collides": collides,
		"breakable": breakable,
		"hit": breakable,
		"collision_rects": collision_rects.duplicate(true),
	}


func _build_south_center_anchor(footprint: Vector2i) -> Vector2:
	return Vector2(
		float(footprint.x * GameConstants.TILE_SIZE) / 2.0,
		float(footprint.y * GameConstants.TILE_SIZE)
	)
