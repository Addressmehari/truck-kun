@tool
extends Node2D

# The surface points of this chunk
var points := PackedVector2Array() :
	set(val):
		points = val
		rebuild_grass()

# Grass styling variables
var color := Color(0, 0.9, 0.46, 1) :
	set(val):
		color = val
		queue_redraw()

var road_seed := 12345 :
	set(val):
		road_seed = val
		rebuild_grass()

var chunk_index := 9999 :
	set(val):
		chunk_index = val
		rebuild_grass()

var chunk_width := 3000.0

# Reference to the road node (to check tunnel locations)
var road: StaticBody2D = null :
	set(val):
		road = val
		rebuild_grass()

# Exported/assigned grass textures passed from the road
var textures: Array = [] :
	set(val):
		textures = val
		rebuild_grass()

# Exported/assigned SpriteFrames passed from the road (frame-based slicing)
var sprite_frames: SpriteFrames = null :
	set(val):
		sprite_frames = val
		rebuild_grass()

# Wind animation properties
var time := 0.0
var wind_speed := 3.0
var wind_amplitude := 6.0

# Cached grass blades, flowers, and sprites data to avoid allocations in draw loop
var blades := []
var flowers := []
var sprites := []

func _ready() -> void:
	# Enable processing only at runtime for dynamic wind sway animation
	set_process(not Engine.is_editor_hint())
	rebuild_grass()

func _process(delta: float) -> void:
	time += delta
	queue_redraw()

# Checks if a given absolute X coordinate is inside a tunnel
func _is_in_tunnel(x: float) -> bool:
	if not road:
		return false
	
	var check_range = [chunk_index - 1, chunk_index, chunk_index + 1] if chunk_index != 9999 else range(-5, 50)
	for idx in check_range:
		var tunnel = road.call("get_tunnel_at_chunk", idx)
		if tunnel and not tunnel.is_empty():
			var tunnel_x = tunnel["x"]
			var half_width = tunnel["width"] / 2.0
			var padding = 200.0
			if abs(x - tunnel_x) <= half_width + padding:
				return true
	return false

# Pre-computes all grass blades, flowers, or sprites once when points or road changes
func rebuild_grass() -> void:
	blades.clear()
	flowers.clear()
	sprites.clear()
	
	if points.size() < 2 or not road:
		return

	var rng = RandomNumberGenerator.new()
	rng.seed = hash(str(road_seed) + "_grass_" + str(chunk_index))

	# Extract textures from SpriteFrames if assigned
	var active_textures := []
	if sprite_frames and sprite_frames.has_animation("default"):
		var count = sprite_frames.get_frame_count("default")
		for f in range(count):
			var tex = sprite_frames.get_frame_texture("default", f)
			if tex:
				active_textures.append(tex)
				
	# Fall back to raw textures array if SpriteFrames is empty/null
	if active_textures.is_empty():
		active_textures = textures

	# If we have textures to spawn (from SpriteFrames or raw array), spawn them!
	if not active_textures.is_empty():
		var size = active_textures.size()
		var has_grass = size > 0
		var has_flowers = size > 2
		var has_bushes = size > 5
		
		for i in range(points.size() - 1):
			var p1 = points[i]
			var p2 = points[i + 1]
			var segment_vector = p2 - p1
			var segment_length = segment_vector.length()
			if segment_length < 0.1:
				continue
				
			var segment_dir = segment_vector / segment_length
			
			# Calculate local road curvature (slope change) to detect straight sections
			var prev_idx = i - 1 if i > 0 else 0
			var prev_angle = (points[i] - points[prev_idx]).angle() if i > 0 else segment_dir.angle()
			
			var next_idx = i + 2 if i < points.size() - 2 else points.size() - 1
			var next_pt1 = points[i + 1]
			var next_pt2 = points[next_idx]
			var next_angle = (next_pt2 - next_pt1).angle() if i < points.size() - 2 else segment_dir.angle()
			
			var curvature = max(abs(segment_dir.angle() - prev_angle), abs(next_angle - segment_dir.angle()))
			# Road segment is straight if adjacent angle difference is less than ~0.03 radians
			var is_straight = curvature < 0.03
			
			var dist = 0.0
			while dist < segment_length:
				var t = dist / segment_length
				var pos = p1.lerp(p2, t)
				
				if _is_in_tunnel(pos.x):
					dist += 30.0
					continue
					
				var roll = rng.randf()
				
				# Spawn decisions based on categorized frames:
				# 1. Bushes: Frame 5, 6 (requires flat/straight road section, no sway)
				if is_straight and roll < 0.12 and has_bushes:
					var frame_idx = rng.randi_range(5, min(6, size - 1))
					var texture = active_textures[frame_idx]
					var scale_val = 0.25 * rng.randf_range(0.9, 1.1) # 2x grass scale (0.125 * 2)
					
					sprites.append({
						"pos": pos,
						"texture": texture,
						"sway_phase": 0.0,
						"scale": Vector2(scale_val, scale_val),
						"slope_angle": segment_dir.angle(),
						"can_sway": false
					})
					dist += rng.randf_range(30.0, 45.0) # Spawn spacing for bushes
					
				# 2. Flowers: Frame 2, 3, 4 (can sway, size varies a little)
				elif roll < 0.32 and has_flowers:
					var frame_idx = rng.randi_range(2, min(4, size - 1))
					var texture = active_textures[frame_idx]
					var scale_val = 0.125 * rng.randf_range(0.7, 1.3) # Varies around grass scale
					
					sprites.append({
						"pos": pos,
						"texture": texture,
						"sway_phase": rng.randf_range(0.0, PI * 2),
						"scale": Vector2(scale_val, scale_val),
						"slope_angle": segment_dir.angle(),
						"can_sway": true
					})
					dist += rng.randf_range(16.0, 26.0) # Medium spacing
					
				# 3. Grass: Frame 0, 1 (can sway, small and frequent)
				else:
					var frame_idx = rng.randi_range(0, min(1, size - 1)) if has_grass else 0
					var texture = active_textures[frame_idx]
					var scale_val = 0.125 * rng.randf_range(0.85, 1.15) # Scaled down 8 times (1/8 = 0.125)
					
					sprites.append({
						"pos": pos,
						"texture": texture,
						"sway_phase": rng.randf_range(0.0, PI * 2),
						"scale": Vector2(scale_val, scale_val),
						"slope_angle": segment_dir.angle(),
						"can_sway": true
					})
					dist += rng.randf_range(8.0, 14.0) # Dense spacing for grass
	else:
		# Fallback to optimized procedural line-based grass
		var grass_spacing := rng.randf_range(14.0, 20.0)
		
		for i in range(points.size() - 1):
			var p1 = points[i]
			var p2 = points[i + 1]
			var segment_vector = p2 - p1
			var segment_length = segment_vector.length()
			if segment_length < 0.1:
				continue
				
			var segment_dir = segment_vector / segment_length
			var normal = Vector2(-segment_dir.y, segment_dir.x).normalized()
			
			var dist = 0.0
			while dist < segment_length:
				var t = dist / segment_length
				var pos = p1.lerp(p2, t)
				
				if _is_in_tunnel(pos.x):
					dist += grass_spacing
					continue
					
				var base_up = (Vector2.UP * 0.75 + normal * 0.25).normalized()
				var base_right = Vector2(-base_up.y, base_up.x)
				
				var blades_count = rng.randi_range(3, 5)
				for b in range(blades_count):
					var max_height = rng.randf_range(8.0, 18.0)
					var slant = rng.randf_range(-0.15, 0.15)
					
					var color_group = 1 # main
					var color_roll = rng.randf()
					if color_roll < 0.35:
						color_group = 0 # dark
					elif color_roll > 0.75:
						color_group = 2 # light
						
					var sway_phase = rng.randf_range(0.0, PI * 2)
					var blade_up = (base_up + base_right * slant).normalized()
					
					blades.append({
						"base": pos,
						"up": blade_up,
						"height": max_height,
						"color_group": color_group,
						"sway_phase": sway_phase
					})
					
					if rng.randf() < 0.03:
						flowers.append({
							"blade_idx": blades.size() - 1,
							"color_idx": rng.randi() % 3
						})
				
				dist += rng.randf_range(12.0, 18.0)

func _draw() -> void:
	# If textures/sprites are active, draw them
	if not sprites.is_empty():
		for sprite in sprites:
			# Calculate dynamic wind sway angle (only if this category sways)
			var sway = 0.0
			if sprite.can_sway:
				sway = sin(time * wind_speed + sprite.pos.x * 0.03 + sprite.sway_phase) * (wind_amplitude * 0.015)
			var angle = sprite.slope_angle + sway
			
			if sprite.texture:
				var tex: Texture2D = sprite.texture
				var size = tex.get_size()
				
				# Set translation, rotation, and scale for rotating from the bottom-center base
				draw_set_transform(sprite.pos, angle, sprite.scale)
				# Draw bottom-centered; draw_texture_rect natively supports AtlasTextures/slicing
				draw_texture_rect(tex, Rect2(-size * Vector2(0.5, 1.0), size), false)
			else:
				# Set transform for the placeholder
				draw_set_transform(sprite.pos, angle, sprite.scale)
				
				# Developer placeholder: semi-transparent green box with a bright green outline
				var ph_rect = Rect2(-10, -24, 20, 24)
				draw_rect(ph_rect, Color(0.0, 0.4, 0.2, 0.6))
				draw_rect(ph_rect, Color(0.0, 0.9, 0.46, 1.0), false, 1.5)
				
				# Inner cross indicating an image placeholder
				draw_line(Vector2(-5, -17), Vector2(5, -7), Color(0.0, 0.9, 0.46, 1.0), 1.0)
				draw_line(Vector2(5, -17), Vector2(-5, -7), Color(0.0, 0.9, 0.46, 1.0), 1.0)
				
		# Restore identity transform
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
		
	# Fallback to optimized line grass
	if blades.is_empty():
		return

	# Color variations for depth
	var main_color := color
	var dark_color := color.darkened(0.25).lerp(Color(0.05, 0.15, 0.08, 1.0), 0.2)
	var light_color := color.lightened(0.15).lerp(Color(0.8, 0.95, 0.4, 1.0), 0.15)
	
	var flower_colors = [
		Color(1.0, 0.92, 0.2),  # Buttercup Yellow
		Color(1.0, 0.4, 0.5),   # Wild Pink
		Color(0.95, 0.95, 0.95) # Daisy White
	]

	# Group lines by color to draw them in batches
	var dark_lines := PackedVector2Array()
	var main_lines := PackedVector2Array()
	var light_lines := PackedVector2Array()

	# Keep track of blade tip positions for drawing flowers
	var tips := PackedVector2Array()
	tips.resize(blades.size())

	# Calculate sway and populate line batches
	for i in range(blades.size()):
		var blade = blades[i]
		var sway = sin(time * wind_speed + blade.base.x * 0.03 + blade.sway_phase) * wind_amplitude
		var tip = blade.base + blade.up * blade.height + Vector2.RIGHT * sway
		tips[i] = tip
		
		if blade.color_group == 0:
			dark_lines.append(blade.base)
			dark_lines.append(tip)
		elif blade.color_group == 1:
			main_lines.append(blade.base)
			main_lines.append(tip)
		else:
			light_lines.append(blade.base)
			light_lines.append(tip)

	# Draw all blades using highly optimized multiline draw calls
	if not dark_lines.is_empty():
		draw_multiline(dark_lines, dark_color, 2.0)
	if not main_lines.is_empty():
		draw_multiline(main_lines, main_color, 2.0)
	if not light_lines.is_empty():
		draw_multiline(light_lines, light_color, 2.0)

	# Draw flowers at the tips of their respective blades
	for flower in flowers:
		var blade_idx: int = flower.blade_idx
		if blade_idx < tips.size():
			var flower_pos = tips[blade_idx]
			var flower_color = flower_colors[flower.color_idx]
			
			draw_circle(flower_pos, 1.8, flower_color)
			# Add central yellow dot for pink/white flowers
			if flower.color_idx != 0:
				draw_circle(flower_pos, 0.7, flower_colors[0])
