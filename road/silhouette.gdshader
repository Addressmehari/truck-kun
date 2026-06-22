shader_type canvas_item;

uniform bool active = true;
uniform vec4 silhouette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec4 tex_color = texture(TEXTURE, UV);
	if (active) {
		// Output the silhouette color, preserving transparency from both texture and canvas modulate/vertex color
		COLOR = vec4(silhouette_color.rgb, tex_color.a * COLOR.a * silhouette_color.a);
	}
}
