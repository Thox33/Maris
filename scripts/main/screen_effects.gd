extends Node
## Owns all fullscreen/camera-layer visual effects.
## Lives in main.tscn so its lifecycle is tied to the game scene, not a player.
##
## Effects live in a CanvasLayer child — no nodes leak to the scene root.
## Add new screen effects here: damage flash, vignette, pause blur, etc.
##
## Usage:
##   ScreenEffects.set_underwater(true / false)

@onready var _underwater_overlay: ColorRect = $CanvasLayer/UnderwaterOverlay


func _ready() -> void:
	_underwater_overlay.size = get_viewport().get_visible_rect().size
	get_viewport().size_changed.connect(_on_viewport_resized)


## Enables or disables the underwater distortion + tint overlay.
## Call this from any system that knows whether the local player is submerged.
func set_underwater(enabled: bool) -> void:
	_underwater_overlay.visible = enabled


func _on_viewport_resized() -> void:
	_underwater_overlay.size = get_viewport().get_visible_rect().size
