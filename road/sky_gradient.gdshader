shader_type canvas_item;

uniform vec4 top_color : source_color = vec4(0.12, 0.05, 0.22, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.95, 0.25, 0.12, 1.0);
uniform float gradient_offset : hint_range(-1.0, 1.0) = 0.0;
uniform float gradient_power : hint_range(0.1, 10.0) = 1.0;

void fragment() {
	// UV.y is 0 at top, 1 at bottom
	float t = clamp(UV.y + gradient_offset, 0.0, 1.0);
	t = pow(t, gradient_power);
	COLOR = mix(top_color, bottom_color, t);
}
