shader_type canvas_item;
/// Animated shimmer for liquid ground tiles (water + lava).
/// Applied directly to LiquidLayer (TileMapLayer).
///
/// Uses FRAGCOORD for world-space wave patterns so the ripple flows
/// continuously across tile boundaries rather than resetting per tile.
/// The base tile texture provides the colour identity (blue = water,
/// orange/red = lava); the shader adds the motion on top.

/// How fast the wave pattern moves. Higher = choppier.
uniform float wave_speed: hint_range(0.0, 4.0) = 1.0;
/// Spatial frequency of the wave pattern relative to tile size.
uniform float wave_scale: hint_range(0.5, 8.0) = 2.0;
/// How strongly the brightness oscillates (0 = none, 0.3 = strong).
uniform float shimmer_strength: hint_range(0.0, 0.4) = 0.20;

void fragment() {
	vec4 base = texture(TEXTURE, UV);

	// Tile-relative world coordinates — divide by TILE_SIZE so the wave
	// repeats every `wave_scale` tiles rather than every `wave_scale` pixels.
	float tx = FRAGCOORD.x / 16.0 * wave_scale;
	float ty = FRAGCOORD.y / 16.0 * wave_scale;

	// Two out-of-phase sine waves create an organic ripple pattern.
	float wave = sin(tx + TIME * wave_speed) * cos(ty * 0.75 + TIME * wave_speed * 0.6);

	float brightness = 1.0 + wave * shimmer_strength;
	COLOR = vec4(base.rgb * brightness, base.a);
}
