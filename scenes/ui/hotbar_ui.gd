extends CanvasLayer
## Visual hotbar showing the first 10 inventory slots at the bottom of the screen.
## Only active for the local player (multiplayer authority).

var _block_interaction: Node2D
var _inventory_manager: Node
var _terrain_texture: Texture2D

var _slot_panels: Array[PanelContainer] = []
var _slot_icons: Array[TextureRect] = []
var _slot_counts: Array[Label] = []

var _selected_index: int = 0
var _style_normal: StyleBoxFlat
var _style_selected: StyleBoxFlat


func _ready() -> void:
	if not get_parent().is_multiplayer_authority():
		visible = false
		set_process_unhandled_input(false)
		return

	_block_interaction = get_parent().get_node("BlockInteraction")
	_inventory_manager = get_tree().root.get_node("Main/InventoryManager")
	_terrain_texture = load("res://assets/tilesets/terrain_tiles.png")

	_create_styles()
	_build_slots()

	_selected_index = _block_interaction.selected_hotbar_slot
	_slot_panels[_selected_index].add_theme_stylebox_override("panel", _style_selected)

	_inventory_manager.local_slot_changed.connect(_on_slot_changed)
	_refresh_all_slots()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode
		if key >= KEY_1 and key <= KEY_9:
			_select_slot(key - KEY_1)
			get_viewport().set_input_as_handled()
		elif key == KEY_0:
			_select_slot(9)
			get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_select_slot(
				(_selected_index - 1 + GameConstants.HOTBAR_SIZE) % GameConstants.HOTBAR_SIZE
			)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_select_slot((_selected_index + 1) % GameConstants.HOTBAR_SIZE)
			get_viewport().set_input_as_handled()


func _select_slot(index: int) -> void:
	if index == _selected_index:
		return
	_slot_panels[_selected_index].add_theme_stylebox_override("panel", _style_normal)
	_selected_index = index
	_slot_panels[_selected_index].add_theme_stylebox_override("panel", _style_selected)
	_block_interaction.selected_hotbar_slot = index


func _on_slot_changed(slot_index: int) -> void:
	if slot_index < GameConstants.HOTBAR_SIZE:
		_update_slot(slot_index)


func _refresh_all_slots() -> void:
	for i: int in range(GameConstants.HOTBAR_SIZE):
		_update_slot(i)


func _update_slot(index: int) -> void:
	if _inventory_manager.local_inventory == null:
		return
	var slot: Dictionary = _inventory_manager.local_inventory.get_slot(index)

	if slot["item_id"] == ItemProperties.NONE:
		_slot_icons[index].texture = null
		_slot_counts[index].text = ""
		return

	var item_props: ItemProperties = ItemProperties.get_properties(slot["item_id"])
	if item_props and item_props.tile_id != -1:
		var tile_props: TileProperties = TileProperties.get_properties(item_props.tile_id)
		if tile_props:
			var atlas_tex := AtlasTexture.new()
			atlas_tex.atlas = _terrain_texture
			var ts: int = GameConstants.TILE_SIZE
			atlas_tex.region = Rect2(
				tile_props.atlas_coord.x * ts,
				tile_props.atlas_coord.y * ts,
				ts,
				ts,
			)
			_slot_icons[index].texture = atlas_tex
	else:
		_slot_icons[index].texture = null

	if slot["count"] > 1:
		_slot_counts[index].text = str(slot["count"])
	else:
		_slot_counts[index].text = ""


func _build_slots() -> void:
	var hbox: HBoxContainer = $MarginContainer/HBoxContainer
	for i: int in range(GameConstants.HOTBAR_SIZE):
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(40, 40)
		panel.add_theme_stylebox_override("panel", _style_normal)

		var icon := TextureRect.new()
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.custom_minimum_size = Vector2(32, 32)
		panel.add_child(icon)

		var count_label := Label.new()
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		count_label.add_theme_font_size_override("font_size", 12)
		count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		count_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		count_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
		panel.add_child(count_label)

		hbox.add_child(panel)
		_slot_panels.append(panel)
		_slot_icons.append(icon)
		_slot_counts.append(count_label)


func _create_styles() -> void:
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0.1, 0.15, 0.25, 0.75)
	_style_normal.border_color = Color(0.3, 0.4, 0.5, 0.8)
	_style_normal.set_border_width_all(1)
	_style_normal.set_corner_radius_all(2)

	_style_selected = StyleBoxFlat.new()
	_style_selected.bg_color = Color(0.15, 0.25, 0.4, 0.85)
	_style_selected.border_color = Color(0.5, 0.8, 1.0, 1.0)
	_style_selected.set_border_width_all(2)
	_style_selected.set_corner_radius_all(2)
