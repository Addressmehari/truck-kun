shader_type canvas_item;

varying vec2 world_pos;

// Road colors
uniform vec4 grass_color : source_color = vec4(0.0, 0.9, 0.46, 1.0);         // Green grass
uniform vec4 grass_shadow_color : source_color = vec4(0.0, 0.65, 0.33, 1.0);  // Darker green shadow
uniform vec4 border_color : source_color = vec4(0.22, 0.15, 0.10, 1.0);      // Brown border (matches ground)

// Voronoi cell settings (should match ground_voronoi.gdshader)
uniform float cell_scale = 0.02;
uniform float border_width = 0.08;
uniform float randomness = 0.85;
uniform float pixel_size = 4.0;
uniform float line_width = 32.0;

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
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
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
	
	// Calculate cell center in world coordinates
	vec2 cell_center = (v_coords + v.xy) / cell_scale;
	
	// Estimate top of the road Y at this pixel
	float road_top_y = world_pos.y - UV.y * line_width;
	
	// Vertical distance of cell center from the road top
	float cell_top_dist = cell_center.y - road_top_y;
	
	// Decide if this cell belongs to the grass (first row of cells)
	float grass_limit = 35.0 + (cell_hash - 0.5) * 15.0;
	
	if (cell_top_dist > grass_limit) {
		discard; // Cut the bottom of the line to follow the cells
	}
	
	// Draw grass color
	vec3 col = grass_color.rgb;
	
	// Add depth shading
	float depth_factor = clamp(UV.y, 0.0, 1.0);
	col = mix(col, grass_shadow_color.rgb, depth_factor * 0.35);
	
	// Draw cell borders
	float border_mask = step(border_width, dist_to_border);
	if (border_mask < 0.5) {
		col = border_color.rgb;
	}
	
	COLOR = vec4(col, 1.0);
}
