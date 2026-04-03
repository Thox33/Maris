extends Node
class_name OverheadSource

signal overhead_changed

@export var anchor_path: NodePath
@export var show_name: bool = true
@export var show_health_bar: bool = false
@export var show_mana_bar: bool = false

var display_name: String = ""
var overhead_visible: bool = true
var current_health: float = 0.0
var max_health: float = 0.0
var current_mana: float = 0.0
var max_mana: float = 0.0
var status_icons: Array[Texture2D] = []


func _ready() -> void:
	add_to_group("overhead_sources")
	call_deferred("_register_with_manager")


func _exit_tree() -> void:
	var manager := _get_manager()
	if manager != null:
		manager.unregister_source(self)


func set_display_name(value: String) -> void:
	var safe_value := value.strip_edges()
	if display_name == safe_value:
		return
	display_name = safe_value
	overhead_changed.emit()


func set_overhead_visible(value: bool) -> void:
	if overhead_visible == value:
		return
	overhead_visible = value
	overhead_changed.emit()


func set_health(current: float, maximum: float, visible: bool = true) -> void:
	var safe_max := maxf(maximum, 0.0)
	var safe_current := clampf(current, 0.0, safe_max) if safe_max > 0.0 else 0.0
	var changed := (
		not is_equal_approx(current_health, safe_current)
		or not is_equal_approx(max_health, safe_max)
		or show_health_bar != visible
	)
	current_health = safe_current
	max_health = safe_max
	show_health_bar = visible
	if changed:
		overhead_changed.emit()


func set_mana(current: float, maximum: float, visible: bool = true) -> void:
	var safe_max := maxf(maximum, 0.0)
	var safe_current := clampf(current, 0.0, safe_max) if safe_max > 0.0 else 0.0
	var changed := (
		not is_equal_approx(current_mana, safe_current)
		or not is_equal_approx(max_mana, safe_max)
		or show_mana_bar != visible
	)
	current_mana = safe_current
	max_mana = safe_max
	show_mana_bar = visible
	if changed:
		overhead_changed.emit()


func set_status_icons(icons: Array[Texture2D]) -> void:
	status_icons = icons.duplicate()
	overhead_changed.emit()


func get_anchor_global_position() -> Vector2:
	var anchor := get_node_or_null(anchor_path) as Node2D
	if anchor != null:
		return anchor.global_position
	var owner_2d := get_parent() as Node2D
	if owner_2d != null:
		return owner_2d.global_position
	return Vector2.ZERO


func get_overhead_state() -> Dictionary:
	var health_ratio := 0.0
	if max_health > 0.0:
		health_ratio = current_health / max_health

	var mana_ratio := 0.0
	if max_mana > 0.0:
		mana_ratio = current_mana / max_mana

	return {
		"display_name": display_name,
		"visible": overhead_visible,
		"show_name": show_name,
		"show_health_bar": show_health_bar and max_health > 0.0,
		"show_mana_bar": show_mana_bar and max_mana > 0.0,
		"health_ratio": health_ratio,
		"mana_ratio": mana_ratio,
		"status_icons": status_icons,
	}


func _register_with_manager() -> void:
	var manager := _get_manager()
	if manager != null:
		manager.register_source(self)


func _get_manager() -> Node:
	return get_tree().root.get_node_or_null("Main/OverheadLayer")
