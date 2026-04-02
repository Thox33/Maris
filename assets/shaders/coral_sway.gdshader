shader_type canvas_item;
// Gentle swaying motion for coral tiles.
// Apply as a material on the TerrainLayer or a secondary overlay layer.
// Uses per-tile phase/amplitude variation so neighboring corals do not move in lockstep.

uniform float sway_amount : hint_range(0.0, 5.0) = 2.5;
uniform float sway_speed : hint_range(0.1, 3.0) = 1.3;
uniform float tile_size = 16.0;
uniform float phase_jitter : hint_range(0.0, 6.28) = 2.4;
uniform float amplitude_jitter : hint_range(0.0, 1.0) = 0.35;
uniform float directional_bias : hint_range(0.0, 1.0) = 0.2;

float hash_1(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void vertex() {
	// Infer a stable tile coordinate so each coral tile gets its own phase offset.
	vec2 tile_origin = VERTEX - UV * tile_size;
	vec2 tile_coord = floor((tile_origin + vec2(0.5)) / tile_size);
	float tile_hash = hash_1(tile_coord);
	float tile_phase = tile_hash * phase_jitter;
	float tile_amplitude = sway_amount * mix(1.0 - amplitude_jitter, 1.0 + amplitude_jitter, tile_hash);
	float tile_direction = mix(-directional_bias, directional_bias, hash_1(tile_coord + vec2(19.4, 7.2)));

	// Anchor the base and let the tips move more strongly.
	float top_factor = clamp(1.0 - UV.y, 0.0, 1.0);
	float bend_profile = top_factor * top_factor;
	float sway_wave = sin(TIME * sway_speed + tile_phase + tile_coord.x * 0.35 + tile_coord.y * 0.18);
	float sway = (sway_wave + tile_direction) * tile_amplitude * bend_profile;
	VERTEX.x += sway;
}
