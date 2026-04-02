shader_type canvas_item;
// Full-screen water distortion shader.
// Apply to a ColorRect covering the viewport.
// Creates a gentle wave effect over everything.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float wave_speed : hint_range(0.1, 3.0) = 0.8;
uniform float wave_strength : hint_range(0.0, 5.0) = 1.5;
uniform float wave_frequency : hint_range(1.0, 20.0) = 8.0;
uniform vec4 tint_color : source_color = vec4(0.05, 0.15, 0.35, 0.12);

void fragment() {
	vec2 uv = SCREEN_UV;

	// Two overlapping sine waves for organic movement.
	float offset_x = sin(uv.y * wave_frequency + TIME * wave_speed) * wave_strength * 0.001;
	float offset_y = cos(uv.x * wave_frequency * 0.7 + TIME * wave_speed * 0.8) * wave_strength * 0.0008;

	vec4 screen_color = texture(screen_texture, uv + vec2(offset_x, offset_y));

	// Subtle blue tint.
	COLOR = mix(screen_color, tint_color, tint_color.a);
}
