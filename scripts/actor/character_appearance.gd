class_name CharacterAppearance
extends RefCounted

const DEFAULT_SKIN_TONE_ID: String = "pearl"
const DEFAULT_HAIR_STYLE_ID: String = "short_round"
const DEFAULT_HAIR_COLOR_ID: String = "kelp_black"
const DEFAULT_TOP_COLOR_ID: String = "abyss_blue"
const DEFAULT_BOTTOM_COLOR_ID: String = "abyss_blue"

const _SKIN_TONES := [
	{
		"id": "pearl",
		"label": "Pearl",
		"base": Color(0.95, 0.83, 0.72, 1.0),
		"shadow": Color(0.75, 0.62, 0.52, 1.0),
		"highlight": Color(1.0, 0.93, 0.84, 1.0),
	},
	{
		"id": "sand",
		"label": "Sand",
		"base": Color(0.86, 0.72, 0.58, 1.0),
		"shadow": Color(0.65, 0.53, 0.41, 1.0),
		"highlight": Color(0.94, 0.82, 0.68, 1.0),
	},
	{
		"id": "bronze",
		"label": "Bronze",
		"base": Color(0.69, 0.52, 0.38, 1.0),
		"shadow": Color(0.49, 0.35, 0.24, 1.0),
		"highlight": Color(0.8, 0.62, 0.46, 1.0),
	},
	{
		"id": "deep_umber",
		"label": "Deep Umber",
		"base": Color(0.45, 0.31, 0.22, 1.0),
		"shadow": Color(0.29, 0.19, 0.13, 1.0),
		"highlight": Color(0.58, 0.41, 0.29, 1.0),
	},
]

const _HAIR_STYLES := [
	{
		"id": "short_round",
		"label": "Short Round",
	},
]

const _HAIR_COLORS := [
	{
		"id": "kelp_black",
		"label": "Kelp Black",
		"base": Color(0.11, 0.13, 0.16, 1.0),
		"shadow": Color(0.06, 0.08, 0.1, 1.0),
		"highlight": Color(0.21, 0.24, 0.29, 1.0),
	},
	{
		"id": "drift_brown",
		"label": "Drift Brown",
		"base": Color(0.31, 0.22, 0.16, 1.0),
		"shadow": Color(0.2, 0.13, 0.09, 1.0),
		"highlight": Color(0.43, 0.31, 0.24, 1.0),
	},
	{
		"id": "salt_blonde",
		"label": "Salt Blonde",
		"base": Color(0.92, 0.78, 0.43, 1.0),
		"shadow": Color(0.68, 0.53, 0.24, 1.0),
		"highlight": Color(1.0, 0.89, 0.58, 1.0),
	},
	{
		"id": "foam_white",
		"label": "Foam White",
		"base": Color(0.88, 0.92, 0.95, 1.0),
		"shadow": Color(0.67, 0.73, 0.8, 1.0),
		"highlight": Color(0.97, 0.99, 1.0, 1.0),
	},
]

const _OUTFIT_COLORS := [
	{
		"id": "abyss_blue",
		"label": "Abyss Blue",
		"base": Color(0.55, 0.78, 1.0, 1.0),
		"shadow": Color(0.28, 0.46, 0.67, 1.0),
		"highlight": Color(0.78, 0.9, 1.0, 1.0),
	},
	{
		"id": "reef_teal",
		"label": "Reef Teal",
		"base": Color(0.44, 0.96, 0.86, 1.0),
		"shadow": Color(0.18, 0.58, 0.52, 1.0),
		"highlight": Color(0.7, 1.0, 0.95, 1.0),
	},
	{
		"id": "sun_gold",
		"label": "Sun Gold",
		"base": Color(1.0, 0.86, 0.42, 1.0),
		"shadow": Color(0.73, 0.56, 0.18, 1.0),
		"highlight": Color(1.0, 0.95, 0.65, 1.0),
	},
	{
		"id": "coral_red",
		"label": "Coral Red",
		"base": Color(1.0, 0.53, 0.47, 1.0),
		"shadow": Color(0.71, 0.28, 0.24, 1.0),
		"highlight": Color(1.0, 0.72, 0.67, 1.0),
	},
]


static func create_default_appearance() -> Dictionary:
	return {
		"skin_tone_id": DEFAULT_SKIN_TONE_ID,
		"hair_style_id": DEFAULT_HAIR_STYLE_ID,
		"hair_color_id": DEFAULT_HAIR_COLOR_ID,
		"top_color_id": DEFAULT_TOP_COLOR_ID,
		"bottom_color_id": DEFAULT_BOTTOM_COLOR_ID,
	}


static func normalize_appearance(raw: Dictionary) -> Dictionary:
	return {
		"skin_tone_id": normalize_skin_tone_id(String(raw.get("skin_tone_id", DEFAULT_SKIN_TONE_ID))),
		"hair_style_id": normalize_hair_style_id(String(raw.get("hair_style_id", DEFAULT_HAIR_STYLE_ID))),
		"hair_color_id": normalize_hair_color_id(String(raw.get("hair_color_id", DEFAULT_HAIR_COLOR_ID))),
		"top_color_id": normalize_outfit_color_id(String(raw.get("top_color_id", DEFAULT_TOP_COLOR_ID))),
		"bottom_color_id": normalize_outfit_color_id(String(raw.get("bottom_color_id", DEFAULT_BOTTOM_COLOR_ID))),
	}


static func create_appearance_from_outfit_index(index: int) -> Dictionary:
	var outfit_id := get_outfit_color_id(index)
	return {
		"skin_tone_id": DEFAULT_SKIN_TONE_ID,
		"hair_style_id": DEFAULT_HAIR_STYLE_ID,
		"hair_color_id": DEFAULT_HAIR_COLOR_ID,
		"top_color_id": outfit_id,
		"bottom_color_id": outfit_id,
	}


static func get_outfit_option_count() -> int:
	return _OUTFIT_COLORS.size()


static func get_outfit_option_label(index: int) -> String:
	var entry := _get_entry_by_index(_OUTFIT_COLORS, index)
	return String(entry.get("label", "Outfit"))


static func get_outfit_color_id(index: int) -> String:
	var entry := _get_entry_by_index(_OUTFIT_COLORS, index)
	return String(entry.get("id", DEFAULT_TOP_COLOR_ID))


static func get_outfit_preview_color(index: int) -> Color:
	return get_outfit_color(get_outfit_color_id(index))


static func find_outfit_option_index(color_id: String) -> int:
	var normalized := normalize_outfit_color_id(color_id)
	for index in range(_OUTFIT_COLORS.size()):
		if String(_OUTFIT_COLORS[index].get("id", "")) == normalized:
			return index
	return 0


static func normalize_skin_tone_id(value: String) -> String:
	return _normalize_id(_SKIN_TONES, value, DEFAULT_SKIN_TONE_ID)


static func normalize_hair_style_id(value: String) -> String:
	return _normalize_id(_HAIR_STYLES, value, DEFAULT_HAIR_STYLE_ID)


static func normalize_hair_color_id(value: String) -> String:
	return _normalize_id(_HAIR_COLORS, value, DEFAULT_HAIR_COLOR_ID)


static func normalize_outfit_color_id(value: String) -> String:
	return _normalize_id(_OUTFIT_COLORS, value, DEFAULT_TOP_COLOR_ID)


static func get_skin_tone_color(color_id: String) -> Color:
	return get_palette_base(get_skin_tone_palette(color_id))


static func get_hair_color(color_id: String) -> Color:
	return get_palette_base(get_hair_color_palette(color_id))


static func get_outfit_color(color_id: String) -> Color:
	return get_palette_base(get_outfit_color_palette(color_id))


static func get_skin_tone_palette(color_id: String) -> Dictionary:
	return _get_entry_by_id(_SKIN_TONES, color_id, DEFAULT_SKIN_TONE_ID)


static func get_hair_color_palette(color_id: String) -> Dictionary:
	return _get_entry_by_id(_HAIR_COLORS, color_id, DEFAULT_HAIR_COLOR_ID)


static func get_outfit_color_palette(color_id: String) -> Dictionary:
	return _get_entry_by_id(_OUTFIT_COLORS, color_id, DEFAULT_TOP_COLOR_ID)


static func get_palette_base(palette: Dictionary) -> Color:
	return palette.get("base", Color.WHITE) as Color


static func get_palette_shadow(palette: Dictionary) -> Color:
	return palette.get("shadow", get_palette_base(palette)) as Color


static func get_palette_highlight(palette: Dictionary) -> Color:
	return palette.get("highlight", get_palette_base(palette)) as Color


static func _normalize_id(entries: Array, value: String, fallback_id: String) -> String:
	for entry_variant in entries:
		var entry := entry_variant as Dictionary
		var id := String(entry.get("id", ""))
		if id == value:
			return id
	return fallback_id


static func _get_entry_by_index(entries: Array, index: int) -> Dictionary:
	if index < 0 or index >= entries.size():
		return entries[0] as Dictionary
	return entries[index] as Dictionary


static func _get_entry_by_id(entries: Array, value: String, fallback_id: String) -> Dictionary:
	var normalized := _normalize_id(entries, value, fallback_id)
	for entry_variant in entries:
		var entry := entry_variant as Dictionary
		if String(entry.get("id", "")) == normalized:
			return entry
	return entries[0] as Dictionary
