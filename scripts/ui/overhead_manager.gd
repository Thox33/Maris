extends CanvasLayer

const ENTITY_OVERHEAD_SCENE := preload("res://scenes/ui/entity_overhead.tscn")

var _entries: Dictionary = {}

@onready var _root: Control = $Root


func _ready() -> void:
	add_to_group("overhead_managers")
	for source: OverheadSource in get_tree().get_nodes_in_group("overhead_sources"):
		register_source(source)


func _process(_delta: float) -> void:
	var canvas_transform := get_viewport().get_canvas_transform()
	var stale_ids: Array[int] = []

	for source_id: int in _entries.keys():
		var entry: Dictionary = _entries[source_id]
		var source := entry["source"] as OverheadSource
		var widget := entry["widget"] as Control

		if source == null or not is_instance_valid(source) or widget == null or not is_instance_valid(widget):
			stale_ids.append(source_id)
			continue

		var screen_pos: Vector2 = canvas_transform * source.get_anchor_global_position()
		widget.position = Vector2(
			roundf(screen_pos.x - (widget.size.x * 0.5)),
			roundf(screen_pos.y - widget.size.y)
		)

	for source_id: int in stale_ids:
		_remove_entry(source_id)


func register_source(source: OverheadSource) -> void:
	if source == null or not is_instance_valid(source):
		return
	var source_id := source.get_instance_id()
	if _entries.has(source_id):
		_refresh_source(source)
		return

	var widget := ENTITY_OVERHEAD_SCENE.instantiate() as Control
	_root.add_child(widget)
	_entries[source_id] = {
		"source": source,
		"widget": widget,
	}

	source.overhead_changed.connect(_on_source_changed.bind(source))
	_refresh_source(source)


func unregister_source(source: OverheadSource) -> void:
	if source == null:
		return
	_remove_entry(source.get_instance_id())


func _on_source_changed(source: OverheadSource) -> void:
	_refresh_source(source)


func _refresh_source(source: OverheadSource) -> void:
	if source == null or not is_instance_valid(source):
		return
	var entry: Dictionary = _entries.get(source.get_instance_id(), {})
	var widget := entry.get("widget") as Control
	if widget == null or not is_instance_valid(widget):
		return
	if widget.has_method("apply_state"):
		widget.apply_state(source.get_overhead_state())


func _remove_entry(source_id: int) -> void:
	var entry: Dictionary = _entries.get(source_id, {})
	var widget := entry.get("widget") as Control
	if widget != null and is_instance_valid(widget):
		widget.queue_free()
	_entries.erase(source_id)
