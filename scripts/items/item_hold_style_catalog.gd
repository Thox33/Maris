class_name ItemHoldStyleCatalog
extends RefCounted

const STYLE_SMALL_ITEM := "small_item"
const STYLE_TOOL_UP_RIGHT := "tool_up_right"

static var _styles: Dictionary = {
	STYLE_SMALL_ITEM: {
		"scale": Vector2(0.35, 0.35),
		"grip_mode": "bottom_center",
		"grip_pixel_offset": Vector2(-1, 0),
	},
	STYLE_TOOL_UP_RIGHT: {
		"scale": Vector2(0.9, 0.9),
		"grip_mode": "bottom_center",
		"grip_pixel_offset": Vector2(-1, -3),
	},
}


static func get_style(style_id: String) -> Dictionary:
	var resolved_style_id := style_id
	if resolved_style_id.is_empty() or not _styles.has(resolved_style_id):
		resolved_style_id = STYLE_SMALL_ITEM
	return (_styles.get(resolved_style_id, {}) as Dictionary).duplicate(true)
