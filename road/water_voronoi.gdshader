shader_type canvas_item;

uniform vec4 blue_bg : source_color = vec4(0.08, 0.28, 0.38, 1.0);
uniform vec4 blue_shadow : source_color = vec4(0.04, 0.16, 0.24, 1.0);
uniform vec4 web_color : source_color = vec4(0.25, 0.65, 0.75, 1.0);

uniform float pixel_size : hint_range(1.0, 16.0) = 4.0;
uniform float cell_scale : hint_range(0.001, 0.1) = 0.015;
uniform float line_thickness : hint_range(0.01, 0.5) = 0.04;
uniform float wave_speed : hint_range(0.01, 5.0) = 0.5;
uniform float opacity : hint_range(0.0, 1.0) = 0.8;
uniform vec2 shadow_offset = vec2(3.0, 5.0);

// Interactive player uniforms
uniform vec2 player_position;
uniform float player_velocity_length;

// Blood Spread uniforms
uniform vec2 blood_position;
uniform float blood_radius = 0.0;
uniform vec4 blood_color : source_color = vec4(0.48, 0.02, 0.08, 0.85);

varying vec2 local_pos;
varying vec2 global_pos;

void vertex() {
	local_pos = VERTEX;
	global_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// 2D Hash to return a vec2 point in [0, 1]
vec2 hash2d_vec2(vec2 p) {
	float hx = fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
	float hy = fract(sin(dot(p, vec2(269.5, 183.3))) * 43758.5453123);
	return vec2(hx, hy);
}

// Inigo Quilez Voronoi Borders / Edge Distance
float voronoi_borders(vec2 p) {
	vec2 ip = floor(p);
	vec2 fp = fract(p);
	
	vec2 mg, mr;
	float md = 8.0;
	
	// First pass: find closest cell center
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbor = vec2(float(x), float(y));
			vec2 point = hash2d_vec2(ip + neighbor);
			
			// Animate cells organically
			point = 0.5 + 0.5 * sin(TIME * wave_speed + point * 6.2831);
			
			vec2 r = neighbor + point - fp;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = neighbor;
			}
		}
	}
	
	// Second pass: find distance to the closest border/edge
	md = 8.0;
	for (int y = -2; y <= 2; y++) {
		for (int x = -2; x <= 2; x++) {
			vec2 neighbor = mg + vec2(float(x), float(y));
			vec2 point = hash2d_vec2(ip + neighbor);
			point = 0.5 + 0.5 * sin(TIME * wave_speed + point * 6.2831);
			
			vec2 r = neighbor + point - fp;
			
			if (dot(mr - r, mr - r) > 0.00001) {
				float d = dot(0.5 * (mr + r), normalize(r - mr));
				md = min(md, d);
			}
		}
	}
	return md;
}

void fragment() {
	// Calculate interactive ripple offset (movement-based waves)
	vec2 ripple_offset = vec2(0.0);
	float dist = distance(global_pos, player_position);
	float ripple_radius = 180.0;
	
	if (dist < ripple_radius) {
		float wave = sin(dist * 0.15 - TIME * 12.0);
		vec2 dir = normalize(global_pos - player_position + vec2(0.001));
		float speed_factor = clamp(player_velocity_length / 200.0, 0.0, 1.0);
		float ripple_fade = smoothstep(ripple_radius, 0.0, dist);
		// Distort local coordinates to warp the water mesh
		ripple_offset = dir * wave * 6.0 * ripple_fade * speed_factor;
	}
	
	// Pixelate position with ripple offset applied
	vec2 p = floor((local_pos + ripple_offset) / pixel_size) * pixel_size;
	
	// Scale position to match desired cell density
	vec2 uv = p * cell_scale;
	
	// Calculate distance to cell boundaries (caustic lines)
	float edge = voronoi_borders(uv);
	
	// Calculate distance to cell boundaries with offset coordinate for depth shadow
	vec2 uv_shadow = (p - shadow_offset) * cell_scale;
	float edge_shadow = voronoi_borders(uv_shadow);
	
	// Calculate dynamic line thickness based on distance to player (position-based line tearing)
	float cut_radius = 55.0;
	float wave_distortion = sin(dist * 0.2 - TIME * 15.0) * 8.0;
	float web_dissolve = smoothstep(cut_radius * 0.4, cut_radius + wave_distortion, dist);
	float current_thickness = line_thickness * web_dissolve;
	
	// Step thresholds for sharp pixel art outlines
	float web_mask = step(edge, current_thickness);
	float shadow_mask = step(edge_shadow, current_thickness + 0.02);
	
	// Combine layers
	vec4 final_color = blue_bg;
	
	if (shadow_mask > 0.0) {
		final_color = blue_shadow;
	}
	if (web_mask > 0.0) {
		final_color = web_color;
	}
	
	// --- Blood Spread Effect ---
	if (blood_radius > 0.0) {
		float dist_to_blood = distance(global_pos, blood_position);
		if (dist_to_blood < blood_radius + 40.0) {
			// Warps the circular boundary into realistic organic plumes
			float blood_noise = voronoi_borders(global_pos * 0.015 - vec2(TIME * 0.08, TIME * 0.04)) * 35.0;
			float bleed_dist = dist_to_blood + blood_noise;
			float blood_factor = smoothstep(blood_radius, blood_radius * 0.25, bleed_dist);
			
			if (blood_factor > 0.0) {
				// Mix in dark venous blood color
				final_color.rgb = mix(final_color.rgb, blood_color.rgb, blood_factor * blood_color.a);
				// Darken caustics inside the blood for deep underwater contrast
				if (web_mask > 0.0) {
					final_color.rgb = mix(final_color.rgb, vec3(0.08, 0.01, 0.03), blood_factor * 0.65);
				}
			}
		}
	}
	
	COLOR = vec4(final_color.rgb, final_color.a * opacity);
}
