shader_type canvas_item;

varying vec2 world_pos;

// Color settings
uniform vec4 color_a : source_color = vec4(0.38, 0.27, 0.18, 1.0);     // Brown
uniform vec4 color_b : source_color = vec4(0.53, 0.40, 0.28, 1.0);     // Light Brown
uniform vec4 border_color : source_color = vec4(0.22, 0.15, 0.10, 1.0);  // Dark brown borders

// Stone settings
uniform vec4 stone_color_a : source_color = vec4(0.42, 0.44, 0.46, 1.0); // Dark grey stone
uniform vec4 stone_color_b : source_color = vec4(0.58, 0.60, 0.62, 1.0); // Light grey stone
uniform float stone_chance = 0.08;     // Chance of a cell being stone (0.0 = none, 1.0 = all)

// Voronoi cell settings
uniform float cell_scale = 0.02;       // Scale of cells (lower is larger cells)
uniform float border_width = 0.08;     // Width of cell borders
uniform float randomness = 0.85;       // Distortion of cells (0.0 = perfect grid, 1.0 = highly irregular)

// Pixelation settings
uniform float pixel_size = 4.0;       // Size of pixelated blocks (1.0 = normal, larger = more pixelated)
uniform float shading_steps = 12.0;    // Number of steps in depth shading (0.0 = smooth)

// System configuration for transition math (should match road template styling)
uniform vec4 fill_color : source_color = vec4(0.12, 0.12, 0.14, 1.0);
uniform vec4 line_color : source_color = vec4(0.0, 0.9, 0.46, 1.0);

// Hash function for cellular random centers
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

// 2D Voronoi returning:
// xy: vector from cell center to current pixel
// z: minimum distance to closest edge
// w: random cell hash/ID
vec4 voronoi(vec2 x, float rand) {
	vec2 n = floor(x);
	vec2 f = fract(x);

	vec2 mg, mr;
	float md = 8.0;
	
	// First pass: find closest cell center
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash2(n + g) * rand;
			vec2 r = g + o - f;
			float d = dot(r, r);

			if (d < md) {
				md = d;
				mr = r;
				mg = g;
			}
		}
	}

	// Second pass: find distance to borders/edges
	md = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 o = hash2(n + g) * rand;
			vec2 r = g + o - f;

			if (dot(mr - r, mr - r) > 0.00001) {
				float d = dot(0.5 * (mr + r), normalize(r - mr));
				md = min(md, d);
			}
		}
	}

	// Cell ID based on hash of cell coordinate
	float cell_hash = fract(sin(dot(n + mg, vec2(12.9898, 78.233))) * 43758.5453);
	return vec4(mr, md, cell_hash);
}

void vertex() {
	// Transform local vertex to world coordinates for seamless alignment across road chunks
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Calculate top and bottom target vertex colors dynamically to construct the gradient
	vec4 top_color = mix(fill_color + (1.0 - fill_color) * 0.12, line_color, 0.12);
	vec4 bottom_color = fill_color * (1.0 - 0.65);
	
	// Project current vertex COLOR onto the gradient line to extract interpolation factor (t)
	vec3 dir = top_color.rgb - bottom_color.rgb;
	float denom = dot(dir, dir);
	float t = 0.0;
	if (denom > 0.0001) {
		t = clamp(dot(COLOR.rgb - bottom_color.rgb, dir) / denom, 0.0, 1.0);
	}
	
	// Quantize t for stepped pixel shading
	if (shading_steps > 0.001) {
		t = floor(t * shading_steps) / shading_steps;
	}
	
	// Pixelate positions in world coordinate space
	vec2 pixelated_pos = world_pos;
	if (pixel_size > 1.001) {
		pixelated_pos = floor(world_pos / pixel_size) * pixel_size;
	}
	
	// Sample Voronoi using pixelated world positions
	vec2 v_coords = pixelated_pos * cell_scale;
	vec4 v = voronoi(v_coords, randomness);
	float dist_to_border = v.z;
	float cell_hash = v.w;
	
	// Determine cell color (dirt vs stone) based on cell hash
	vec3 cell_color;
	if (cell_hash < stone_chance) {
		// Stone cell
		float stone_hash = fract(cell_hash * 37.123);
		cell_color = mix(stone_color_a.rgb, stone_color_b.rgb, stone_hash);
	} else {
		// Dirt cell
		float dirt_hash = (cell_hash - stone_chance) / (1.0 - stone_chance);
		cell_color = mix(color_a.rgb, color_b.rgb, dirt_hash);
	}
	
	// Add stepped internal shadow/glow centered in each cell for retro 2.5D volume
	float center_dist = length(v.xy);
	float inner_glow = 0.0;
	if (center_dist < 0.18) {
		inner_glow = 0.08;
	} else if (center_dist > 0.42) {
		inner_glow = -0.06;
	}
	cell_color += vec3(inner_glow);
	
	// Sharp pixelated outlines (using step instead of smoothstep)
	float border_mask = step(border_width, dist_to_border);
	vec3 texture_color = mix(border_color.rgb, cell_color, border_mask);
	
	// Blend the Voronoi pattern with the dark bottom color based on height gradient
	vec3 final_color = mix(bottom_color.rgb, texture_color, t);
	
	// Subtly blend with green top_color right at the top surface for an organic moss transition
	if (t > 0.85) {
		float grass_blend = (t - 0.85) / 0.15;
		if (shading_steps > 0.001) {
			grass_blend = floor(grass_blend * 3.0) / 3.0;
		}
		final_color = mix(final_color, top_color.rgb, grass_blend * 0.4);
	}
	
	COLOR = vec4(final_color, COLOR.a);
}
