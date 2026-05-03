class_name StructureCatalog
extends RefCounted

var _world_object_catalog = preload("res://scripts/world/world_object_catalog.gd").new()

var registry: Dictionary = _build_registry()


func get_definition(structure_id: String):
	return registry.get(structure_id)


func _build_registry() -> Dictionary:
	var result: Dictionary = {}
	var by_legacy_structure_id: Dictionary = _world_object_catalog.get("by_legacy_structure_id")
	for structure_id in by_legacy_structure_id.keys():
		var definition = _world_object_catalog.call(
			"get_definition_by_structure_id",
			String(structure_id)
		)
		if definition != null and String(definition.kind) == "structure":
			result[String(structure_id)] = definition
	return result
