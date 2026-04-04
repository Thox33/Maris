@tool
extends EditorScript
## Run this script once via the Godot editor (File > Run) to generate
## improved placeholder pixel art for tiles and player.
## After running, you can delete this script.

const TW: int = 16
## Atlas layout: 8 columns, 2 rows.
## Row 0: terrain (sand, stone item/full, tall-structure body, tall-structure cap, + future variants)
## Row 1: coral variants (6 types)
const COLS: int = 8
const ROWS: int = 2


func _run() -> void:
	_generate_terrain_tiles()
	_generate_player_sprite()
	print("Art generation complete!")


func _generate_terrain_tiles() -> void:
	var img := Image.create(TW * COLS, TW * ROWS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	# --- Row 0: Terrain ---
	_draw_sand(img, 0, 0)
	_draw_stone(img, 1, 0)
	_draw_stone_body(img, 2, 0)
	_draw_stone_cap(img, 3, 0)

	# --- Row 1: Coral variants ---
	_draw_coral_branch(img, 0, 1)
	_draw_coral_fan(img, 1, 1)
	_draw_coral_kelp(img, 2, 1)
	_draw_coral_brain(img, 3, 1)
	_draw_coral_anemone(img, 4, 1)
	_draw_coral_tube(img, 5, 1)

	img.save_png("res://assets/tilesets/terrain_tiles.png")
	print("Saved terrain_tiles.png (%dx%d)" % [TW * COLS, TW * ROWS])


# --- Terrain tiles ---


func _draw_sand(img: Image, col: int, row: int) -> void:
	var ox: int = col * TW
	var oy: int = row * TW
	var base := Color(0.76, 0.70, 0.50)
	var dark := Color(0.65, 0.58, 0.40)
	var light := Color(0.85, 0.78, 0.58)
	for y in range(TW):
		for x in range(TW):
			var c := base
			if (x + y * 3) % 7 == 0:
				c = dark
			elif (x * 2 + y) % 9 == 0:
				c = light
			if x == 4 and y == 10:
				c = Color(0.9, 0.85, 0.75)
			if x == 11 and y == 5:
				c = Color(0.88, 0.82, 0.70)
			img.set_pixel(ox + x, oy + y, c)


func _draw_stone(img: Image, col: int, row: int) -> void:
	var ox: int = col * TW
	var oy: int = row * TW
	var base := Color(0.45, 0.45, 0.50)
	var dark := Color(0.32, 0.32, 0.38)
	var light := Color(0.55, 0.55, 0.60)
	for y in range(TW):
		for x in range(TW):
			var c := base
			if x == 3 and y > 2 and y < 12:
				c = dark
			if x == 4 and y > 5 and y < 14:
				c = dark
			if y == 8 and x > 6 and x < 14:
				c = dark
			if (x * 5 + y * 3) % 11 == 0:
				c = light
			if (x + y * 7) % 13 == 0:
				c = dark
			img.set_pixel(ox + x, oy + y, c)


func _draw_stone_body(img: Image, col: int, row: int) -> void:
	var tile := _build_stone_tile()
	var ox: int = col * TW
	var oy: int = row * TW
	for y in range(1, TW):
		for x in range(TW):
			var c := tile[y][x] as Color
			var shade := 0.12 + (float(y) / float(TW)) * 0.20
			c = c.lerp(Color(0.15, 0.17, 0.22), shade)
			if y == 1:
				c = c.lerp(Color(0.82, 0.84, 0.88), 0.24)
			img.set_pixel(ox + x, oy + y, c)


func _draw_stone_cap(img: Image, col: int, row: int) -> void:
	var tile := _build_stone_tile()
	var ox: int = col * TW
	var oy: int = row * TW
	for y in range(6):
		for x in range(TW):
			var c := tile[y][x] as Color
			c = c.lerp(Color(0.82, 0.84, 0.90), 0.22)
			if y == 5:
				c = c.lerp(Color(0.62, 0.65, 0.72), 0.18)
			img.set_pixel(ox + x, oy + y, c)
	for x in range(TW):
		var shadow := Color(0.28, 0.30, 0.36)
		img.set_pixel(ox + x, oy + 5, img.get_pixel(ox + x, oy + 5).lerp(shadow, 0.20))


func _build_stone_tile() -> Array:
	var pixels: Array = []
	var base := Color(0.45, 0.45, 0.50)
	var dark := Color(0.32, 0.32, 0.38)
	var light := Color(0.55, 0.55, 0.60)
	for y in range(TW):
		var row: Array = []
		for x in range(TW):
			var c := base
			if x == 3 and y > 2 and y < 12:
				c = dark
			if x == 4 and y > 5 and y < 14:
				c = dark
			if y == 8 and x > 6 and x < 14:
				c = dark
			if (x * 5 + y * 3) % 11 == 0:
				c = light
			if (x + y * 7) % 13 == 0:
				c = dark
			row.append(c)
		pixels.append(row)
	return pixels


# --- Coral variants ---


func _draw_coral_branch(img: Image, col: int, row: int) -> void:
	## Classic branching coral — pinkish red, Y-shaped branches.
	var ox: int = col * TW
	var oy: int = row * TW
	var base := Color(0.85, 0.35, 0.45)
	var dark := Color(0.70, 0.25, 0.35)
	var light := Color(0.95, 0.50, 0.55)
	var tip := Color(1.0, 0.65, 0.70)
	for y in range(TW):
		for x in range(TW):
			var hit := false
			# Main trunk.
			if x >= 6 and x <= 9 and y >= 6:
				hit = true
			# Left branch.
			if x >= 3 and x <= 5 and y >= 3 and y <= 10:
				hit = true
			# Right branch.
			if x >= 10 and x <= 12 and y >= 2 and y <= 9:
				hit = true
			# Left tip.
			if x >= 2 and x <= 4 and y >= 1 and y <= 3:
				hit = true
			# Right tip.
			if x >= 11 and x <= 13 and y >= 0 and y <= 2:
				hit = true
			if hit:
				var c := base
				if y <= 3:
					c = tip
				elif (x + y) % 3 == 0:
					c = light
				elif (x * 2 + y) % 5 == 0:
					c = dark
				img.set_pixel(ox + x, oy + y, c)


func _draw_coral_fan(img: Image, col: int, row: int) -> void:
	## Wide fan shape — purple/violet palette.
	var ox: int = col * TW
	var oy: int = row * TW
	var base := Color(0.55, 0.30, 0.70)
	var dark := Color(0.40, 0.20, 0.55)
	var light := Color(0.70, 0.45, 0.85)
	var tip := Color(0.82, 0.60, 0.95)
	for y in range(TW):
		for x in range(TW):
			var hit := false
			# Wide fan: spreads from narrow base to wide top.
			var half_width: int = maxi(1, (TW - y) * 7 / TW)
			var cx: int = 7
			if x >= cx - half_width and x <= cx + half_width and y >= 2 and y <= 14:
				hit = true
			# Stem.
			if x >= 6 and x <= 8 and y >= 12:
				hit = true
			# Cut holes for fan texture.
			if hit and y < 10 and (x + y) % 3 == 0 and absi(x - cx) > 1:
				hit = false
			if hit:
				var c := base
				if y <= 4:
					c = tip
				elif (x + y * 2) % 4 == 0:
					c = light
				elif (x * 3 + y) % 7 == 0:
					c = dark
				img.set_pixel(ox + x, oy + y, c)


func _draw_coral_kelp(img: Image, col: int, row: int) -> void:
	## Tall wavy kelp strands — green palette.
	var ox: int = col * TW
	var oy: int = row * TW
	var base := Color(0.25, 0.60, 0.35)
	var dark := Color(0.15, 0.45, 0.25)
	var light := Color(0.40, 0.75, 0.45)
	var tip := Color(0.55, 0.85, 0.55)
	# Three wavy strands at different x positions.
	var strand_x: Array[int] = [4, 8, 12]
	for strand in range(3):
		var sx: int = strand_x[strand]
		for y in range(TW):
			# Sine wave offset per strand.
			var wave: int = int(sin(float(y) * 0.8 + float(strand) * 2.1) * 1.5)
			var px: int = sx + wave
			if px < 0 or px >= TW:
				continue
			# Draw 1-2 pixel wide strand.
			var c := base
			if y <= 2:
				c = tip
			elif (y + strand) % 3 == 0:
				c = light
			elif (y + strand) % 5 == 0:
				c = dark
			img.set_pixel(ox + px, oy + y, c)
			if px + 1 < TW:
				img.set_pixel(ox + px + 1, oy + y, dark if y > 2 else base)


func _draw_coral_brain(img: Image, col: int, row: int) -> void:
	## Round bumpy brain coral — orange/yellow palette.
	var ox: int = col * TW
	var oy: int = row * TW
	var base := Color(0.90, 0.60, 0.25)
	var dark := Color(0.75, 0.45, 0.15)
	var light := Color(1.0, 0.75, 0.40)
	var groove := Color(0.60, 0.35, 0.12)
	var center := Vector2(7.5, 8.5)
	var radius: float = 6.5
	for y in range(TW):
		for x in range(TW):
			var dist: float = Vector2(float(x), float(y)).distance_to(center)
			if dist > radius:
				continue
			var c := base
			# Groovy brain pattern.
			var pattern: int = (x * 3 + y * 2) % 6
			if pattern == 0:
				c = groove
			elif pattern == 1:
				c = dark
			elif pattern == 4:
				c = light
			# Highlight on top.
			if y <= 4 and dist < radius - 1.5:
				c = light
			img.set_pixel(ox + x, oy + y, c)


func _draw_coral_anemone(img: Image, col: int, row: int) -> void:
	## Sea anemone — magenta/pink tentacles spreading upward.
	var ox: int = col * TW
	var oy: int = row * TW
	var base := Color(0.80, 0.25, 0.55)
	var dark := Color(0.60, 0.15, 0.40)
	var light := Color(0.95, 0.45, 0.70)
	var tip := Color(1.0, 0.70, 0.85)
	# Base/body.
	for y in range(10, TW):
		for x in range(3, 13):
			var c := base
			if (x + y) % 4 == 0:
				c = dark
			img.set_pixel(ox + x, oy + y, c)
	# Tentacles — several thin strands curving outward.
	var tentacle_base_x: Array[int] = [3, 5, 7, 9, 11]
	for t in range(tentacle_base_x.size()):
		var bx: int = tentacle_base_x[t]
		var spread: float = float(bx - 7) * 0.15
		for y in range(10):
			var ty: int = 9 - y
			var tx: int = bx + int(float(y) * spread + sin(float(y) * 1.2 + float(t)) * 0.8)
			if tx < 0 or tx >= TW:
				continue
			var c := light if y > 6 else base
			if y >= 8:
				c = tip
			img.set_pixel(ox + tx, oy + ty, c)


func _draw_coral_tube(img: Image, col: int, row: int) -> void:
	## Tube coral cluster — teal/cyan, multiple short tubes.
	var ox: int = col * TW
	var oy: int = row * TW
	var base := Color(0.20, 0.60, 0.65)
	var dark := Color(0.12, 0.45, 0.50)
	var light := Color(0.35, 0.75, 0.80)
	var rim := Color(0.50, 0.85, 0.90)
	# Define tube positions: (center_x, top_y, width).
	var tubes: Array[Vector3i] = [
		Vector3i(4, 5, 3),
		Vector3i(8, 3, 3),
		Vector3i(12, 6, 3),
		Vector3i(6, 8, 2),
		Vector3i(10, 7, 2),
	]
	for tube in tubes:
		var cx: int = tube.x
		var top_y: int = tube.y
		var hw: int = tube.z / 2
		for y in range(top_y, TW):
			for x in range(cx - hw, cx + hw + 1):
				if x < 0 or x >= TW:
					continue
				var c := base
				if y == top_y:
					c = rim
				elif x == cx - hw or x == cx + hw:
					c = dark
				elif (x + y) % 4 == 0:
					c = light
				img.set_pixel(ox + x, oy + y, c)


func _generate_player_sprite() -> void:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var suit := Color(0.2, 0.5, 0.7)
	var suit_light := Color(0.3, 0.6, 0.8)
	var visor := Color(0.6, 0.9, 1.0)
	var visor_shine := Color(0.85, 0.95, 1.0)
	var skin := Color(0.9, 0.75, 0.6)
	var outline := Color(0.12, 0.25, 0.35)
	var flipper := Color(0.15, 0.4, 0.55)

	# Body outline and fill (rows 3-12, cols 4-11).
	for y in range(3, 13):
		for x in range(4, 12):
			img.set_pixel(x, y, suit)

	# Lighter suit center.
	for y in range(4, 12):
		for x in range(6, 10):
			img.set_pixel(x, y, suit_light)

	# Head / mask area (rows 2-6, cols 5-10).
	for y in range(2, 7):
		for x in range(5, 11):
			img.set_pixel(x, y, suit)

	# Visor (rows 3-5, cols 6-9).
	for y in range(3, 6):
		for x in range(6, 10):
			img.set_pixel(x, y, visor)
	img.set_pixel(7, 3, visor_shine)
	img.set_pixel(6, 3, visor_shine)

	# Arms (rows 6-9).
	for y in range(6, 10):
		img.set_pixel(3, y, suit)
		img.set_pixel(12, y, suit)

	# Hands.
	img.set_pixel(3, 10, skin)
	img.set_pixel(12, 10, skin)

	# Flippers (rows 13-14).
	for x in range(4, 7):
		img.set_pixel(x, 13, flipper)
		img.set_pixel(x, 14, flipper)
	for x in range(9, 12):
		img.set_pixel(x, 13, flipper)
		img.set_pixel(x, 14, flipper)

	# Outline — darken edge pixels.
	var outlined := img.duplicate()
	for y in range(16):
		for x in range(16):
			if img.get_pixel(x, y).a < 0.1:
				# Check if any neighbor is opaque.
				var has_neighbor := false
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var nx: int = x + dx
						var ny: int = y + dy
						if nx >= 0 and nx < 16 and ny >= 0 and ny < 16:
							if img.get_pixel(nx, ny).a > 0.5:
								has_neighbor = true
				if has_neighbor:
					outlined.set_pixel(x, y, outline)
	outlined.save_png("res://assets/sprites/player.png")
	print("Saved player.png (16x16)")
