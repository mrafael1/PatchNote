// Full-screen "the build is being rewritten" glitch over the frozen world.
// strength 0 = invisible. Slices of the screen shift sideways, the colour channels
// split, and faint scanlines and a green tint come in with strength.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;

float hash(float n) {
	return fract(sin(n * 127.1 + seed * 311.7) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float t = floor(TIME * 24.0);
	// Horizontal bands, a few of which jump sideways each step.
	float band = floor(uv.y * 28.0);
	float r = hash(band + t * 13.0);
	float shift = (r > 1.0 - 0.35 * strength) ? (hash(band * 7.0 + t) - 0.5) * 0.12 * strength : 0.0;
	uv.x = clamp(uv.x + shift, 0.0, 1.0);
	float split = 0.006 * strength;
	vec3 col;
	col.r = texture(screen_tex, uv + vec2(split, 0.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - vec2(split, 0.0)).b;
	float scan = 0.85 + 0.15 * sin(SCREEN_UV.y * 720.0 * 3.14159);
	col *= mix(1.0, scan, strength);
	col = mix(col, col * vec3(0.7, 1.15, 0.8), 0.5 * strength);
	COLOR = vec4(col, 1.0);
}
