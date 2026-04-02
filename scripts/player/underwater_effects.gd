extends Node2D
## Spawns ambient underwater particle effects around the local player.
## Adds bubble particles and a fullscreen water distortion shader.

var _bubbles: CPUParticles2D
var _water_overlay: ColorRect


func _ready() -> void:
	if not get_parent().is_multiplayer_authority():
		return
	_setup_bubbles()
	_setup_water_shader()


func _setup_bubbles() -> void:
	_bubbles = CPUParticles2D.new()
	_bubbles.emitting = true
	_bubbles.amount = 20
	_bubbles.lifetime = 4.0
	_bubbles.explosiveness = 0.0

	# Spread across visible area.
	_bubbles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_bubbles.emission_rect_extents = Vector2(220, 130)

	# Float upward slowly.
	_bubbles.direction = Vector2(0, -1)
	_bubbles.initial_velocity_min = 8.0
	_bubbles.initial_velocity_max = 18.0
	_bubbles.gravity = Vector2(0, 0)

	# Gentle horizontal drift.
	_bubbles.spread = 20.0

	# Tiny bubbles.
	_bubbles.scale_amount_min = 0.5
	_bubbles.scale_amount_max = 2

	# White-blue transparent.
	_bubbles.color = Color(0.7, 0.85, 1.0, 0.3)

	# Fade out.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.7, 0.85, 1.0, 0.0))
	gradient.set_color(1, Color(0.7, 0.85, 1.0, 0.35))
	gradient.add_point(0.7, Color(0.7, 0.85, 1.0, 0.25))
	_bubbles.color_ramp = gradient

	_bubbles.z_index = 5
	add_child(_bubbles)


func _setup_water_shader() -> void:
	var shader := load("res://assets/shaders/underwater.gdshader") as Shader
	if shader == null:
		return

	var mat := ShaderMaterial.new()
	mat.shader = shader

	# CanvasLayer so it renders on top of everything.
	var layer := CanvasLayer.new()
	layer.layer = 100

	_water_overlay = ColorRect.new()
	_water_overlay.material = mat
	_water_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Set size explicitly — anchors don't resolve until the node is in the tree.
	_water_overlay.size = get_viewport_rect().size
	get_viewport().size_changed.connect(
		func() -> void: _water_overlay.size = get_viewport_rect().size
	)

	layer.add_child(_water_overlay)
	get_tree().get_root().call_deferred("add_child", layer)
