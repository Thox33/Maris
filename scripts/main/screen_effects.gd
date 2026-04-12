extends Node
## Owns all fullscreen/camera-layer visual effects.
## Lives in main.tscn so its lifecycle is tied to the game scene, not a player.
##
## Effects live in a CanvasLayer child — no nodes leak to the scene root.
## Add new screen effects here: damage flash, vignette, pause blur, etc.
