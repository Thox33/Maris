extends Control

@onready var _stack: VBoxContainer = $Stack
@onready var _name_label: Label = $Stack/NameLabel
@onready var _health_bar: ProgressBar = $Stack/HealthBar
@onready var _mana_bar: ProgressBar = $Stack/ManaBar
@onready var _icon_row: HBoxContainer = $Stack/IconRow


func apply_state(state: Dictionary) -> void:
	visible = bool(state.get("visible", true))
	if not visible:
		return

	var show_name: bool = bool(state.get("show_name", true))
	_name_label.visible = show_name
	_name_label.text = String(state.get("display_name", ""))

	var show_health_bar: bool = bool(state.get("show_health_bar", false))
	_health_bar.visible = show_health_bar
	if show_health_bar:
		var health_ratio: float = float(state.get("health_ratio", 0.0))
		_health_bar.value = clampf(health_ratio, 0.0, 1.0) * 100.0

	var show_mana_bar: bool = bool(state.get("show_mana_bar", false))
	_mana_bar.visible = show_mana_bar
	if show_mana_bar:
		var mana_ratio: float = float(state.get("mana_ratio", 0.0))
		_mana_bar.value = clampf(mana_ratio, 0.0, 1.0) * 100.0

	var icons: Array = state.get("status_icons", []) as Array
	for child in _icon_row.get_children():
		child.queue_free()
	_icon_row.visible = not icons.is_empty()
	for icon_variant: Variant in icons:
		var icon := icon_variant as Texture2D
		if icon == null:
			continue
		var rect := TextureRect.new()
		rect.texture = icon
		rect.custom_minimum_size = Vector2(12.0, 12.0)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon_row.add_child(rect)

	reset_size()
