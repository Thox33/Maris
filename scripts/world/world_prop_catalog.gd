class_name WorldPropCatalog
extends RefCounted

var _world_object_catalog = preload("res://scripts/world/world_object_catalog.gd").new()

const EMPTY: int = -1

var registry: Dictionary = _build_registry()
var by_name: Dictionary = _build_by_name()
var coral_variants: Array[int] = _build_coral_variants()
var tree_variants: Array[int] = _build_tree_variants()


func get_definition(prop_id: int):
	return registry.get(prop_id)


func resolve_placement_prop_id(prop_id: int) -> int:
	var definition = get_definition(prop_id)
	if definition == null:
		return prop_id
	if definition.placement_variants.is_empty():
		return prop_id
	var resolved_object_id: String = String(_world_object_catalog.call(
		"resolve_placement_object_id",
		definition.id
	))
	var resolved_definition = _world_object_catalog.call("get_definition", resolved_object_id)
	if resolved_definition == null:
		return prop_id
	return resolved_definition.legacy_prop_id


func get_hit_offset_bounds() -> Dictionary:
	return _world_object_catalog.call("get_hit_offset_bounds_for_props")


func _build_registry() -> Dictionary:
	var result: Dictionary = {}
	var by_legacy_prop_id: Dictionary = _world_object_catalog.get("by_legacy_prop_id")
	for prop_id_variant in by_legacy_prop_id.keys():
		var prop_id := int(prop_id_variant)
		var definition = _world_object_catalog.call("get_definition_by_prop_id", prop_id)
		if definition != null and String(definition.kind) == "prop":
			result[prop_id] = definition
	return result


func _build_by_name() -> Dictionary:
	var result: Dictionary = {}
	for prop_id in registry.keys():
		var definition = registry[prop_id]
		if definition != null:
			result[definition.name] = prop_id
	return result


func _build_coral_variants() -> Array[int]:
	var result: Array[int] = []
	for object_id in _world_object_catalog.get("coral_variants"):
		var definition = _world_object_catalog.call("get_definition", object_id)
		if definition != null and definition.legacy_prop_id >= 0:
			result.append(definition.legacy_prop_id)
	return result


func _build_tree_variants() -> Array[int]:
	var result: Array[int] = []
	for object_id in _world_object_catalog.get("tree_variants"):
		var definition = _world_object_catalog.call("get_definition", object_id)
		if definition != null and definition.legacy_prop_id >= 0:
			result.append(definition.legacy_prop_id)
	return result
