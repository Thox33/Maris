extends Node2D
## Draws chunk boundaries in world-space while the local debug overlay is enabled.

const BORDER_COLOR := Color(0.15, 0.85, 1.0, 0.35)
const BORDER_WIDTH := 1.0

var _chunk_manager: Node
var _enabled: bool = false


func _ready() -> void:
	var world := get_tree().get_root().get_node_or_null("Main/World")
	_chunk_manager = world.get_node_or_null("ChunkManager") if world != null else null
	visible = false
	set_process(false)


func set_enabled(value: bool) -> void:
	if _enabled == value:
		return

	_enabled = value
	visible = value
	set_process(value)
	queue_redraw()


func _process(_delta: float) -> void:
	if _enabled:
		queue_redraw()


func _draw() -> void:
	if not _enabled or _chunk_manager == null:
		return

	var chunk_size_px := GameConstants.CHUNK_SIZE * GameConstants.TILE_SIZE
	var chunk_extent := Vector2(chunk_size_px, chunk_size_px)

	for coord: Vector2i in _chunk_manager.loaded_chunks.keys():
		var origin := Vector2(coord.x * chunk_size_px, coord.y * chunk_size_px)
		draw_rect(Rect2(origin, chunk_extent), BORDER_COLOR, false, BORDER_WIDTH)
