extends Control

var _players_node: Node


func setup_players_node(players_node: Node) -> void:
	_players_node = players_node
	queue_redraw()


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if not visible or _players_node == null:
		return

	var canvas_transform := get_viewport().get_canvas_transform()
	for player in _players_node.get_children():
		if not (player is Node2D):
			continue
		if not player.has_method("get_actor_facing") or not player.has_method("is_actor_side_view_mirrored"):
			continue

		var origin := canvas_transform * (player as Node2D).global_position
		var direction := _get_direction_vector(player)
		if direction != Vector2.ZERO:
			var line_color := Color(0.22, 0.95, 1.0, 0.95)
			var tip := origin + direction * 14.0
			draw_line(origin, tip, line_color, 2.0)
			draw_circle(tip, 2.5, line_color)

		if player.has_method("get_actor_look_dir"):
			_draw_eye_indicator(origin, player.get_actor_look_dir())


func _draw_eye_indicator(player_screen_pos: Vector2, look_dir: Vector2) -> void:
	# Small circle offset to the top-right of the player marker
	const RADIUS := 8.0
	const OFFSET := Vector2(20.0, -20.0)
	var center := player_screen_pos + OFFSET
	var eye_color := Color(1.0, 0.85, 0.2, 0.95)
	draw_arc(center, RADIUS, 0.0, TAU, 24, eye_color, 1.0)
	var pupil := center + look_dir * (RADIUS - 2.0)
	draw_circle(pupil, 2.5, eye_color)


func _get_direction_vector(player: Node) -> Vector2:
	var facing := String(player.get_actor_facing())
	match facing:
		"up":
			return Vector2.UP
		"down":
			return Vector2.DOWN
		"side":
			return Vector2.LEFT if bool(player.is_actor_side_view_mirrored()) else Vector2.RIGHT
		_:
			return Vector2.ZERO
