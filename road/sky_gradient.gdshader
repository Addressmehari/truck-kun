shader_type canvas_item;

uniform vec4 top_color : source_color = vec4(0.02, 0.015, 0.08, 1.0); // Midnight sky
uniform vec4 bottom_color : source_color = vec4(0.2, 0.08, 0.18, 1.0); // Purple sunset horizon
uniform float gradient_offset : hint_range(-1.0, 1.0) = 0.0;
uniform float gradient_power : hint_range(0.1, 10.0) = 1.0;

// Moon settings
uniform bool show_moon = true;
uniform vec2 moon_pos = vec2(0.75, 0.25);
uniform float moon_size = 0.06;
uniform float moon_glow = 0.15;
uniform vec4 moon_color : source_color = vec4(1.0, 0.98, 0.85, 1.0);
uniform vec2 crescent_offset = vec2(0.015, -0.008);

// Star settings
uniform bool show_stars = true;
uniform float star_density = 40.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	// UV.y is 0 at top, 1 at bottom
	float t = clamp(UV.y + gradient_offset, 0.0, 1.0);
	t = pow(t, gradient_power);
	vec4 sky_color = mix(top_color, bottom_color, t);
	
	// Aspect ratio correct UVs
	float aspect = TEXTURE_PIXEL_SIZE.y / TEXTURE_PIXEL_SIZE.x;
	vec2 aspect_uv = vec2(UV.x * aspect, UV.y);
	
	vec4 final_color = sky_color;
	
	// Add stars
	if (show_stars) {
		vec2 grid_uv = aspect_uv * star_density;
		vec2 ipos = floor(grid_uv);
		vec2 fpos = fract(grid_uv);
		
		float h = hash(ipos);
		// Decide if cell has a star (only in upper part of sky to avoid stars near ground)
		if (h > 0.94 && UV.y < 0.6) {
			vec2 offset = vec2(hash(ipos + 1.0), hash(ipos + 2.0)) * 0.8 - 0.4;
			float d = length(fpos - 0.5 - offset);
			float star_val = smoothstep(0.08, 0.0, d) * (h - 0.94) / 0.06;
			final_color.rgb += vec3(star_val);
		}
	}
	
	// Add moon
	if (show_moon) {
		vec2 adj_moon_pos = vec2(moon_pos.x * aspect, moon_pos.y);
		float dist = length(aspect_uv - adj_moon_pos);
		
		// Outer glow (blended additively)
		float glow = smoothstep(moon_size + moon_glow, moon_size, dist) * 0.35;
		
		// Moon shape
		float moon_mask = smoothstep(moon_size + 0.005, moon_size, dist);
		
		// Crescent cut
		vec2 adj_crescent_pos = adj_moon_pos + vec2(crescent_offset.x * aspect, crescent_offset.y);
		float crescent_dist = length(aspect_uv - adj_crescent_pos);
		float crescent_mask = smoothstep(moon_size + 0.005, moon_size, crescent_dist);
		
		float final_moon = clamp(moon_mask - crescent_mask, 0.0, 1.0);
		
		// Add moon and glow to sky
		final_color.rgb = mix(final_color.rgb, moon_color.rgb, final_moon);
		final_color.rgb += moon_color.rgb * glow;
	}
	
	COLOR = final_color;
}
