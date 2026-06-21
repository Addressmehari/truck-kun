shader_type canvas_item;

varying vec2 world_pos;

// Road colors
uniform vec4 grass_color : source_color = vec4(0.0, 0.9, 0.46, 1.0);     // Green grass border
uniform vec4 asphalt_color : source_color = vec4(0.18, 0.18, 0.20, 1.0);   // Dark asphalt body
uniform vec4 stripe_color : source_color = vec4(0.95, 0.85, 0.20, 1.0);    // Yellow dash stripes
uniform vec4 shadow_color : source_color = vec4(0.12, 0.12, 0.14, 1.0);    // Bottom shadow

// Pixel art settings
uniform float pixel_size = 4.0;            // Screen pixel block size
uniform float dash_length = 60.0;          // Length of yellow center dashes in pixels
uniform float dash_gap = 60.0;             // Gap between yellow dashes in pixels

void vertex() {
	// Pass world coordinates for repeating dash calculations
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Divide road width (UV.y) into pixelated horizontal bands
	float pixelated_y = floor(UV.y * 12.0) / 12.0;
	float px = floor(world_pos.x / pixel_size) * pixel_size;
	
	vec3 col;
	
	if (pixelated_y < 0.08) {
		// 1. Top bright grass line (thin top edge)
		col = grass_color.rgb;
	} else if (pixelated_y < 0.15) {
		// 2. Highlight/transition band
		col = mix(grass_color.rgb, asphalt_color.rgb, 0.5);
	} else if (pixelated_y < 0.90) {
		// 3. Asphalt road body (thick pavement extending downwards)
		col = asphalt_color.rgb;
		
		// Render yellow dash lines down the middle of the road
		if (pixelated_y > 0.45 && pixelated_y < 0.55) {
			float period = dash_length + dash_gap;
			float dash_x = mod(px, period);
			if (dash_x < dash_length) {
				col = stripe_color.rgb;
			}
		}
		
		// Add pixelated asphalt texture noise
		float noise = fract(sin(dot(floor(world_pos / pixel_size), vec2(12.9898, 78.233))) * 43758.5453);
		if (noise < 0.07) {
			col -= vec3(0.04);
		} else if (noise > 0.93) {
			col += vec3(0.03);
		}
	} else {
		// 4. Bottom shadow/dirt transition
		col = shadow_color.rgb;
	}
	
	COLOR = vec4(col, 1.0);
}
