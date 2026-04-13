shader_type canvas_item;
/// Stable liquid motion for ground tiles (water + lava).
/// Applied directly to LiquidLayer (TileMapLayer).
///
/// Uses world-space phase so the wave stays fixed in the world when the camera
/// moves. The effect focuses on sideways row motion and subtle crest highlights
/// to read more like water and less like a shadow overlay.

uniform float tile_size: hint_range(8.0, 64.0) = 16.0;
uniform float wave_speed: hint_range(0.0, 4.0) = 1.15;
uniform float wave_scale: hint_range(0.2, 4.0) = 1.0;
uniform float horizontal_strength: hint_range(0.0, 2.0) = 0.9;
uniform float vertical_strength: hint_range(0.0, 1.0) = 0.12;
uniform float highlight_strength: hint_range(0.0, 0.25) = 0.10;
uniform float shadow_strength: hint_range(0.0, 0.15) = 0.03;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 tile_uv_size = TEXTURE_PIXEL_SIZE * tile_size;
	vec2 tile_origin_uv = floor(UV / tile_uv_size) * tile_uv_size;
	vec2 tile_local_uv = UV - tile_origin_uv;
	vec2 wave_uv = world_pos / tile_size * wave_scale;

	float row_wave = sin(wave_uv.y * 4.2 + TIME * wave_speed + wave_uv.x * 0.30);
	float fine_wave = sin(wave_uv.y * 7.6 - TIME * wave_speed * 1.35 + wave_uv.x * 0.18);
	float cross_wave = cos((wave_uv.x + wave_uv.y * 0.7) * 2.1 + TIME * wave_speed * 0.55);

	float offset_x_px = (row_wave * 0.80 + fine_wave * 0.30 + cross_wave * 0.20) * horizontal_strength;
	float offset_y_px = (cross_wave * 0.12 - fine_wave * 0.08) * vertical_strength;
	vec2 distortion_uv = vec2(offset_x_px, offset_y_px) * TEXTURE_PIXEL_SIZE;

	// Keep the sample inside the current atlas cell so neighboring tiles do not bleed in.
	vec2 margin = TEXTURE_PIXEL_SIZE * 0.5;
	vec2 sample_local_uv = clamp(tile_local_uv + distortion_uv, margin, tile_uv_size - margin);
	vec4 base = texture(TEXTURE, tile_origin_uv + sample_local_uv);

	float crest_mask = smoothstep(0.45, 0.95, row_wave * 0.7 + fine_wave * 0.15 + cross_wave * 0.15);
	float trough_mask = smoothstep(0.35, 0.85, -(row_wave * 0.65 + fine_wave * 0.20));
	vec3 color = base.rgb * (1.0 - trough_mask * shadow_strength);
	color += vec3(1.0, 1.0, 1.0) * (crest_mask * highlight_strength);
	COLOR = vec4(color, base.a);
}
