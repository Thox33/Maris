shader_type canvas_item;
// Gentle swaying motion for vegetation.
// Works on tilemap decor layers and on individual prop sprites.

uniform float sway_amount : hint_range(0.0, 5.0) = 4;
uniform float sway_speed : hint_range(0.1, 3.0) = 3;
uniform float tile_size = 16.0;
uniform float sprite_height_px = 16.0;
uniform float rigid_base_px : hint_range(0.0, 16.0) = 0.0;
uniform float phase_jitter : hint_range(0.0, 6.28) = 2.4;
uniform float amplitude_jitter : hint_range(0.0, 1.0) = 0.35;
uniform float directional_bias : hint_range(0.0, 1.0) = 0.2;
uniform float phase_seed = 0.0;
uniform float explicit_phase_mix : hint_range(0.0, 1.0) = 0.0;

float hash_1(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void vertex() {
	// Infer a stable tile coordinate so each plant tile gets its own phase offset.
	vec2 tile_origin = VERTEX - UV * tile_size;
	vec2 tile_coord = floor((tile_origin + vec2(0.5)) / tile_size);
	float tile_hash = hash_1(tile_coord);
	float seeded_hash = hash_1(vec2(phase_seed, phase_seed + 17.3));
	float motion_hash = mix(tile_hash, seeded_hash, explicit_phase_mix);
	float tile_phase = mix(tile_hash * phase_jitter, phase_seed, explicit_phase_mix);
	float tile_amplitude = sway_amount * mix(1.0 - amplitude_jitter, 1.0 + amplitude_jitter, motion_hash);
	float tile_direction = mix(-directional_bias, directional_bias, hash_1(vec2(motion_hash, motion_hash + 19.4)));

	// Anchor the base and let the tips move more strongly.
	float rigid_base_ratio = clamp(rigid_base_px / max(sprite_height_px, 0.001), 0.0, 1.0);
	float top_factor = clamp((1.0 - UV.y - rigid_base_ratio) / max(1.0 - rigid_base_ratio, 0.001), 0.0, 1.0);
	float bend_profile = top_factor * top_factor;
	float sway_wave = sin(TIME * sway_speed + tile_phase + tile_coord.x * 0.35 + tile_coord.y * 0.18);
	float sway = (sway_wave + tile_direction) * tile_amplitude * bend_profile;
	VERTEX.x += sway;
}
