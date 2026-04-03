class_name MenuStyles
extends RefCounted

## Central factory for menu-oriented UI themes.


static func create_theme() -> Theme:
	var theme := Theme.new()

	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.035, 0.09, 0.13, 0.96)
	panel.border_color = Color(0.20, 0.47, 0.54, 0.95)
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(20)
	panel.shadow_color = Color(0.0, 0.0, 0.0, 0.30)
	panel.shadow_size = 16
	panel.shadow_offset = Vector2(0, 12)
	panel.content_margin_left = 26.0
	panel.content_margin_top = 26.0
	panel.content_margin_right = 26.0
	panel.content_margin_bottom = 26.0
	theme.set_stylebox("panel", "PanelContainer", panel)

	var button_normal := _make_box(
		Color(0.08, 0.18, 0.25, 0.98), Color(0.22, 0.53, 0.60, 1.0), 2, 14
	)
	var button_hover := _make_box(
		Color(0.11, 0.24, 0.33, 1.0), Color(0.38, 0.78, 0.84, 1.0), 2, 14
	)
	var button_pressed := _make_box(
		Color(0.06, 0.14, 0.20, 1.0), Color(0.46, 0.86, 0.91, 1.0), 2, 14
	)
	var button_disabled := _make_box(
		Color(0.07, 0.09, 0.11, 0.88), Color(0.15, 0.20, 0.23, 0.88), 2, 14
	)

	for style_name: String in ["normal", "focus"]:
		theme.set_stylebox(style_name, "Button", button_normal)
	theme.set_stylebox("hover", "Button", button_hover)
	theme.set_stylebox("pressed", "Button", button_pressed)
	theme.set_stylebox("disabled", "Button", button_disabled)
	theme.set_color("font_color", "Button", Color(0.93, 0.98, 1.0))
	theme.set_color("font_hover_color", "Button", Color(1.0, 1.0, 1.0))
	theme.set_color("font_pressed_color", "Button", Color(0.93, 0.98, 1.0))
	theme.set_color("font_disabled_color", "Button", Color(0.44, 0.52, 0.57))
	theme.set_font_size("font_size", "Button", 18)
	theme.set_constant("outline_size", "Button", 0)

	var line_normal := _make_box(
		Color(0.03, 0.07, 0.10, 0.98), Color(0.15, 0.33, 0.38, 0.95), 2, 12
	)
	var line_focus := _make_box(
		Color(0.04, 0.09, 0.13, 1.0), Color(0.39, 0.80, 0.85, 1.0), 2, 12
	)
	var line_read_only := _make_box(
		Color(0.05, 0.07, 0.09, 0.94), Color(0.12, 0.16, 0.19, 0.94), 2, 12
	)
	theme.set_stylebox("normal", "LineEdit", line_normal)
	theme.set_stylebox("focus", "LineEdit", line_focus)
	theme.set_stylebox("read_only", "LineEdit", line_read_only)
	theme.set_color("font_color", "LineEdit", Color(0.92, 0.98, 1.0))
	theme.set_color("font_selected_color", "LineEdit", Color(0.04, 0.08, 0.10))
	theme.set_color("selection_color", "LineEdit", Color(0.42, 0.80, 0.86, 0.92))
	theme.set_color("placeholder_color", "LineEdit", Color(0.49, 0.61, 0.67))
	theme.set_color("caret_color", "LineEdit", Color(0.82, 0.96, 1.0))
	theme.set_font_size("font_size", "LineEdit", 16)

	var item_list_normal := _make_box(
		Color(0.025, 0.06, 0.09, 0.94), Color(0.15, 0.33, 0.39, 0.92), 2, 12
	)
	var item_list_focus := _make_box(
		Color(0.03, 0.07, 0.10, 0.98), Color(0.34, 0.73, 0.79, 1.0), 2, 12
	)
	theme.set_stylebox("panel", "ItemList", item_list_normal)
	theme.set_stylebox("focus", "ItemList", item_list_focus)
	theme.set_color("font_color", "ItemList", Color(0.86, 0.95, 0.98))
	theme.set_color("font_selected_color", "ItemList", Color(0.98, 1.0, 1.0))
	theme.set_color("selection_color", "ItemList", Color(0.17, 0.44, 0.50, 0.92))
	theme.set_color("guide_color", "ItemList", Color(0.15, 0.22, 0.26, 0.30))
	theme.set_font_size("font_size", "ItemList", 16)

	var separator := StyleBoxLine.new()
	separator.color = Color(0.17, 0.34, 0.39, 0.85)
	separator.thickness = 2
	theme.set_stylebox("separator", "HSeparator", separator)

	theme.set_color("font_color", "Label", Color(0.85, 0.94, 0.98))
	theme.set_font_size("font_size", "Label", 15)

	return theme


static func _make_box(
	bg_color: Color, border_color: Color, border_width: int, corner_radius: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(corner_radius)
	style.content_margin_left = 16.0
	style.content_margin_top = 12.0
	style.content_margin_right = 16.0
	style.content_margin_bottom = 12.0
	return style
