shader_type canvas_item;
// B1 readability: the world loses colour and the edges darken as time slows.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	float grey = dot(col, vec3(0.299, 0.587, 0.114));
	vec3 cold = vec3(grey * 0.9, grey * 0.98, grey * 1.08);
	col = mix(col, cold, amount * 0.85);
	vec2 d = SCREEN_UV - vec2(0.5);
	float vignette = smoothstep(0.25, 0.75, length(d * vec2(1.3, 1.0)));
	col *= 1.0 - vignette * amount * 0.55;
	COLOR = vec4(col, 1.0);
}
