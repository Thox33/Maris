class_name CharacterAppearance
extends RefCounted

const DEFAULT_PRESET_ID: String = "abyss_blue"

const _PRESETS := [
	{
		"id": "abyss_blue",
		"label": "Abyss Blue",
		"color": Color(0.55, 0.78, 1.0, 1.0),
	},
	{
		"id": "reef_teal",
		"label": "Reef Teal",
		"color": Color(0.44, 0.96, 0.86, 1.0),
	},
	{
		"id": "sun_gold",
		"label": "Sun Gold",
		"color": Color(1.0, 0.86, 0.42, 1.0),
	},
	{
		"id": "coral_red",
		"label": "Coral Red",
		"color": Color(1.0, 0.53, 0.47, 1.0),
	},
]


static func get_preset_count() -> int:
	return _PRESETS.size()


static func get_preset_label(index: int) -> String:
	var preset := _get_preset_by_index(index)
	return String(preset.get("label", "Preset"))


static func get_preset_id(index: int) -> String:
	var preset := _get_preset_by_index(index)
	return String(preset.get("id", DEFAULT_PRESET_ID))


static func get_color_for_preset(preset_id: String) -> Color:
	var preset := _get_preset_by_id(preset_id)
	return preset.get("color", Color.WHITE) as Color


static func find_preset_index(preset_id: String) -> int:
	var normalized := normalize_preset_id(preset_id)
	for index in range(_PRESETS.size()):
		if String(_PRESETS[index].get("id", "")) == normalized:
			return index
	return 0


static func normalize_preset_id(preset_id: String) -> String:
	for preset: Dictionary in _PRESETS:
		var id := String(preset.get("id", ""))
		if id == preset_id:
			return id
	return DEFAULT_PRESET_ID


static func _get_preset_by_index(index: int) -> Dictionary:
	if index < 0 or index >= _PRESETS.size():
		return _PRESETS[0]
	return _PRESETS[index]


static func _get_preset_by_id(preset_id: String) -> Dictionary:
	var normalized := normalize_preset_id(preset_id)
	for preset: Dictionary in _PRESETS:
		if String(preset.get("id", "")) == normalized:
			return preset
	return _PRESETS[0]
