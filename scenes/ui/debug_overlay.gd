extends CanvasLayer
## Local-only debug overlay similar to an F3 panel.

var _player: CharacterBody2D
var _label: Label
var _direction_overlay: Control
var _chunk_debug_overlay: Node
var _chunk_manager: Node
var _items_node: Node
var _players_node: Node


func setup_session(chunk_manager: Node, items_node: Node, players_node: Node, chunk_debug_overlay: Node) -> void:
	_chunk_manager = chunk_manager
	_items_node = items_node
	_players_node = players_node
	_chunk_debug_overlay = chunk_debug_overlay


func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	if _player == null or not _player.is_multiplayer_authority():
		visible = false
		set_process(false)
		set_process_unhandled_input(false)
		return

	_label = $MarginContainer/PanelContainer/Label
	_direction_overlay = $DirectionOverlay
	visible = false
	_set_debug_visible(false)
	_update_text()

	if NetworkManager.has_signal("ping_updated"):
		NetworkManager.ping_updated.connect(_on_ping_updated)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			_set_debug_visible(not visible)
			if visible:
				_update_text()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible:
		_update_text()


func _on_ping_updated(_ping_ms: float) -> void:
	if visible:
		_update_text()


func _set_debug_visible(value: bool) -> void:
	visible = value
	if _chunk_debug_overlay != null:
		_chunk_debug_overlay.set_enabled(value)
	if _direction_overlay != null:
		_direction_overlay.visible = value


func _update_text() -> void:
	if _player == null or _label == null:
		return

	var peer_id := multiplayer.get_unique_id()
	var role := "Client"
	if multiplayer.is_server():
		role = "Host"

	var fps := Engine.get_frames_per_second()
	var tile_coord := Vector2i(
		floori(_player.global_position.x / GameConstants.TILE_SIZE),
		floori(_player.global_position.y / GameConstants.TILE_SIZE)
	)
	var chunk_coord := Vector2i(
		floori(float(tile_coord.x) / GameConstants.CHUNK_SIZE),
		floori(float(tile_coord.y) / GameConstants.CHUNK_SIZE)
	)

	var ping_text := "0 ms"
	if not multiplayer.is_server():
		ping_text = "%.1f ms" % NetworkManager.ping_ms

	var loaded_chunks := 0
	if _chunk_manager != null:
		loaded_chunks = _chunk_manager.loaded_chunks.size()

	var player_count := 0
	if _players_node != null:
		player_count = _players_node.get_child_count()

	var item_count := 0
	if _items_node != null:
		item_count = _items_node.get_child_count()

	var facing := "unknown"
	if _player.has_method("get_actor_facing"):
		facing = String(_player.get_actor_facing())
		if facing == "side" and _player.has_method("is_actor_side_view_mirrored"):
			facing = "left" if bool(_player.is_actor_side_view_mirrored()) else "right"

	var locomotion := "unknown"
	if _player.has_method("get_actor_locomotion_state"):
		locomotion = String(_player.get_actor_locomotion_state())

	_label.text = "\n".join([
		"Sandbox Debug",
		"FPS: %d" % fps,
		"Peer: %d (%s)" % [peer_id, role],
		"Ping: %s" % ping_text,
		"Pos: (%.1f, %.1f)" % [_player.global_position.x, _player.global_position.y],
		"Vel: (%.1f, %.1f)" % [_player.velocity.x, _player.velocity.y],
		"Facing: %s" % facing,
		"Locomotion: %s" % locomotion,
		"Tile: %s" % tile_coord,
		"Chunk: %s" % chunk_coord,
		"Loaded chunks: %d" % loaded_chunks,
		"Players: %d" % player_count,
		"Items: %d" % item_count,
		"Pos sync: %.0f Hz" % (1.0 / GameConstants.POSITION_SYNC_INTERVAL),
	])

	if _direction_overlay != null and _direction_overlay.has_method("setup_players_node"):
		_direction_overlay.setup_players_node(_players_node)
