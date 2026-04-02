extends CanvasLayer
## Local-only debug overlay similar to an F3 panel.

var _player: CharacterBody2D
var _label: Label


func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	if _player == null or not _player.is_multiplayer_authority():
		visible = false
		set_process(false)
		set_process_unhandled_input(false)
		return

	_label = $MarginContainer/PanelContainer/Label
	visible = false
	_update_text()

	if NetworkManager.has_signal("ping_updated"):
		NetworkManager.ping_updated.connect(_on_ping_updated)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			visible = not visible
			if visible:
				_update_text()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if visible:
		_update_text()


func _on_ping_updated(_ping_ms: float) -> void:
	if visible:
		_update_text()


func _update_text() -> void:
	if _player == null or _label == null:
		return

	var peer_id := multiplayer.get_unique_id()
	var role := "Client"
	if multiplayer.is_server():
		role = "Host"

	var fps := Engine.get_frames_per_second()
	var world := get_tree().get_root().get_node_or_null("Main/World")
	var chunk_manager := world.get_node_or_null("ChunkManager") if world != null else null
	var items_node := get_tree().get_root().get_node_or_null("Main/Items")
	var players_node := get_tree().get_root().get_node_or_null("Main/Players")
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
	if chunk_manager != null:
		loaded_chunks = chunk_manager.loaded_chunks.size()

	var player_count := 0
	if players_node != null:
		player_count = players_node.get_child_count()

	var item_count := 0
	if items_node != null:
		item_count = items_node.get_child_count()

	_label.text = "\n".join([
		"Sandbox Debug",
		"FPS: %d" % fps,
		"Peer: %d (%s)" % [peer_id, role],
		"Ping: %s" % ping_text,
		"Pos: (%.1f, %.1f)" % [_player.global_position.x, _player.global_position.y],
		"Vel: (%.1f, %.1f)" % [_player.velocity.x, _player.velocity.y],
		"Tile: %s" % tile_coord,
		"Chunk: %s" % chunk_coord,
		"Loaded chunks: %d" % loaded_chunks,
		"Players: %d" % player_count,
		"Items: %d" % item_count,
		"Pos sync: %.0f Hz" % (1.0 / GameConstants.POSITION_SYNC_INTERVAL),
	])
