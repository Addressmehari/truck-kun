@tool
extends Node2D

# Inner class helper for foreground drawing (renders in front of the truck)
class ForegroundNode extends Node2D:
	var parent_decorator: Node2D
	
	func _draw() -> void:
		if parent_decorator:
			parent_decorator._draw_foreground(self)

# The surface points of this chunk
var points := PackedVector2Array() :
	set(val):
		points = val
		rebuild_grass()

# Grass styling variables
var color := Color(0, 0.9, 0.46, 1) :
	set(val):
		color = val
		redraw_all()

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

var density_multiplier := 1.0 :
	set(val):
		density_multiplier = max(0.01, val)
		rebuild_grass()

# Wind animation properties
var time := 0.0
var wind_speed := 3.0
var wind_amplitude := 6.0

# Foreground overlay node instance
var foreground: ForegroundNode = null

# Cached grass blades, flowers, and sprites data to avoid allocations in draw loop
var blades := []
var flowers := []
var sprites := []

# Performance Optimization: Cache camera and physics variables once per process tick
var cached_cam_x := 0.0
var cached_chassis_pos_x := 0.0
var cached_chassis_vel_x := 0.0
var cached_has_chassis := false

func _ready() -> void:
	# Enable processing only at runtime for dynamic wind sway animation
	set_process(not Engine.is_editor_hint())
	
	# Create foreground overlay node
	foreground = ForegroundNode.new()
	foreground.parent_decorator = self
	foreground.z_index = 5 # Higher than truck (default 0)
	add_child(foreground)
	
	rebuild_grass()

func _process(delta: float) -> void:
	time += delta
	
	# Update cached variables once per frame to eliminate heavy queries during drawing
	if not Engine.is_editor_hint() and is_inside_tree():
		var camera = get_viewport().get_camera_2d()
		if camera:
			cached_cam_x = camera.global_position.x
			
		if road:
			var chassis = road.get_node_or_null("../truck/chassis")
			cached_has_chassis = is_instance_valid(chassis)
			if cached_has_chassis:
				cached_chassis_pos_x = chassis.global_position.x
				cached_chassis_vel_x = chassis.linear_velocity.x
		else:
			cached_has_chassis = false
	else:
		cached_has_chassis = false
		
	redraw_all()

func redraw_all() -> void:
	queue_redraw()
	if is_instance_valid(foreground):
		foreground.queue_redraw()

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

# Performance Optimization: O(1) local road height interpolation using cached chunk points
# Avoids expensive dynamic calls, tree traversals, and redundant calculations.
func get_local_road_height(x: float) -> float:
	var count = points.size()
	if count == 0:
		return 0.0
	if x <= points[0].x:
		return points[0].y
	if x >= points[count - 1].x:
		return points[count - 1].y
		
	# Guessing index based on constant step_size (30.0 px)
	var guess = int((x - points[0].x) / 30.0)
	guess = clamp(guess, 0, count - 2)
	
	# Verify guess bounds (highly likely to match)
	if points[guess].x <= x and x <= points[guess + 1].x:
		var t = (x - points[guess].x) / (points[guess + 1].x - points[guess].x)
		return lerp(points[guess].y, points[guess + 1].y, t)
		
	# Safe scan fallback if step sizes are uneven
	for i in range(count - 1):
		if points[i].x <= x and x <= points[i + 1].x:
			var t = (x - points[i].x) / (points[i + 1].x - points[i].x)
			return lerp(points[i].y, points[i + 1].y, t)
			
	return points[count - 1].y

# Pre-computes all grass blades, flowers, or sprites once when points or road changes
func rebuild_grass() -> void:
	blades.clear()
	flowers.clear()
	sprites.clear()
	
	if points.size() < 2 or not road:
		return

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
		
		# Define only the surface grass layer (no parallax)
		var LAYERS = [
			{ "y_offset": 0.0, "y_jitter": 4.0, "parallax": 0.0, "scale_mult": 1.0, "is_fg": false }
		]
		
		for layer_idx in range(LAYERS.size()):
			var layer = LAYERS[layer_idx]
			var rng = RandomNumberGenerator.new()
			# Deterministic seed per layer per chunk to maintain visual consistency
			rng.seed = hash(str(road_seed) + "_grass_" + str(chunk_index) + "_lay_" + str(layer_idx))
			
			# Setup spacing
			var min_space = 16.0 / density_multiplier
			var max_space = 28.0 / density_multiplier
				
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
				var is_straight = curvature < 0.03
				
				var dist = rng.randf_range(0.0, min_space) # Randomize start phase per chunk segment
				while dist < segment_length:
					var t = dist / segment_length
					# Scatter horizontally slightly so vertical layers don't overlap in neat rows
					var pos = p1.lerp(p2, t) + segment_dir * rng.randf_range(-8.0, 8.0)
					
					if _is_in_tunnel(pos.x):
						dist += min_space
						continue
						
					var roll = rng.randf()
					# Organic vertical scattering per sprite instance
					var y_off = layer.y_offset + rng.randf_range(-layer.y_jitter, layer.y_jitter)
					
					# Spawn decisions based on categorized frames:
					# 1. Bushes: Frame 5, 6 (only on surface layer, requires flat/straight road section, no sway)
					if layer_idx == 0 and is_straight and roll < 0.10 and has_bushes:
						var frame_idx = rng.randi_range(5, min(6, size - 1))
						var texture = active_textures[frame_idx]
						var scale_val = 0.25 * rng.randf_range(0.9, 1.1)
						
						sprites.append({
							"pos": pos,
							"texture": texture,
							"sway_phase": 0.0,
							"scale": Vector2(scale_val, scale_val),
							"slope_angle": segment_dir.angle(),
							"can_sway": false,
							"category": "bush",
							"layer_idx": layer_idx,
							"y_offset": y_off,
							"parallax": layer.parallax,
							"scale_mult": layer.scale_mult,
							"is_foreground": layer.is_fg
						})
						dist += rng.randf_range(min_space * 1.5, max_space * 1.5)
						
					# 2. Flowers: Frame 2, 3, 4 (can sway, size varies a little)
					elif roll < 0.30 and has_flowers:
						var frame_idx = rng.randi_range(2, min(4, size - 1))
						var texture = active_textures[frame_idx]
						var scale_val = 0.25 * rng.randf_range(0.7, 1.3)
						
						sprites.append({
							"pos": pos,
							"texture": texture,
							"sway_phase": rng.randf_range(0.0, PI * 2),
							"scale": Vector2(scale_val, scale_val),
							"slope_angle": segment_dir.angle(),
							"can_sway": true,
							"category": "flower",
							"layer_idx": layer_idx,
							"y_offset": y_off,
							"parallax": layer.parallax,
							"scale_mult": layer.scale_mult,
							"is_foreground": layer.is_fg
						})
						dist += rng.randf_range(min_space, max_space)
						
					# 3. Grass: Frame 0, 1 (can sway, small and frequent)
					else:
						var frame_idx = rng.randi_range(0, min(1, size - 1)) if has_grass else 0
						var texture = active_textures[frame_idx]
						var scale_val = 0.25 * rng.randf_range(0.85, 1.15)
						
						sprites.append({
							"pos": pos,
							"texture": texture,
							"sway_phase": rng.randf_range(0.0, PI * 2),
							"scale": Vector2(scale_val, scale_val),
							"slope_angle": segment_dir.angle(),
							"can_sway": true,
							"category": "grass",
							"layer_idx": layer_idx,
							"y_offset": y_off,
							"parallax": layer.parallax,
							"scale_mult": layer.scale_mult,
							"is_foreground": layer.is_fg
						})
						dist += rng.randf_range(min_space * 0.8, max_space * 0.8)
	else:
		# Fallback to optimized procedural line-based grass (only surface layer, no parallax)
		var LAYERS_LINE = [
			{ "y_offset": 0.0, "y_jitter": 4.0, "parallax": 0.0, "scale_mult": 1.0, "is_fg": false }
		]
		
		for layer_idx in range(LAYERS_LINE.size()):
			var layer = LAYERS_LINE[layer_idx]
			var rng = RandomNumberGenerator.new()
			rng.seed = hash(str(road_seed) + "_grass_" + str(chunk_index) + "_line_lay_" + str(layer_idx))
			
			var grass_spacing := rng.randf_range(14.0, 20.0) / density_multiplier
			
			for i in range(points.size() - 1):
				var p1 = points[i]
				var p2 = points[i + 1]
				var segment_vector = p2 - p1
				var segment_length = segment_vector.length()
				if segment_length < 0.1:
					continue
					
				var segment_dir = segment_vector / segment_length
				var normal = Vector2(-segment_dir.y, segment_dir.x).normalized()
				
				var dist = rng.randf_range(0.0, grass_spacing)
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
						var y_off = layer.y_offset + rng.randf_range(-layer.y_jitter, layer.y_jitter)
						
						blades.append({
							"base": pos,
							"up": blade_up,
							"height": max_height,
							"color_group": color_group,
							"sway_phase": sway_phase,
							"y_offset": y_off,
							"parallax": layer.parallax,
							"scale_mult": layer.scale_mult,
							"is_foreground": layer.is_fg
						})
						
						if rng.randf() < 0.03:
							flowers.append({
								"blade_idx": blades.size() - 1,
								"color_idx": rng.randi() % 3
							})
					
					dist += rng.randf_range(12.0, 18.0) / density_multiplier

	redraw_all()

# Draws background elements
func _draw() -> void:
	_draw_elements(self, false)

# Draws foreground elements (called from child ForegroundNode)
func _draw_foreground(canvas: Node2D) -> void:
	_draw_elements(canvas, true)

# Unified drawing logic for both layers
func _draw_elements(canvas: Node2D, render_foreground: bool) -> void:
	# 1. Texture-based sprite rendering
	if not sprites.is_empty():
		for sprite in sprites:
			# Filter by drawing layer
			if sprite.is_foreground != render_foreground:
				continue
				
			# Calculate parallax horizontal shift (using cached camera)
			var offset_x = (sprite.pos.x - cached_cam_x) * sprite.parallax
				
			# Recalculate Y position locally via cached chunk points (Extreme Performance Optimization)
			var actual_x = sprite.pos.x + offset_x
			var actual_y = sprite.pos.y
			if offset_x != 0.0:
				actual_y = get_local_road_height(actual_x)
				
			# Position offset vertically down into the dirt layer
			var draw_pos = Vector2(actual_x, actual_y + sprite.y_offset)
			
			# Calculate wind sway
			var sway = 0.0
			if sprite.can_sway:
				sway = sin(time * wind_speed + draw_pos.x * 0.03 + sprite.sway_phase) * (wind_amplitude * 0.015)
				
			# Calculate truck draft effect (only affects grass category!)
			var draft_rotation := 0.0
			var scale_multiplier := Vector2(sprite.scale_mult, sprite.scale_mult)
			
			if cached_has_chassis and sprite.category == "grass":
				var dx = draw_pos.x - cached_chassis_pos_x
				var dist_x = abs(dx)
				var radius = 250.0
				if dist_x < radius:
					var factor = (radius - dist_x) / radius
					var smooth_factor = factor * factor
					
					var target_draft = clamp(cached_chassis_vel_x * 0.0012 * smooth_factor, -1.1, 1.1)
					draft_rotation = target_draft
					
					scale_multiplier.y *= 1.0 - abs(target_draft) * 0.45
					scale_multiplier.x *= 1.0 + abs(target_draft) * 0.15
					
			var angle = sprite.slope_angle + sway + draft_rotation
			var final_scale = sprite.scale * scale_multiplier
			
			if sprite.texture:
				var tex: Texture2D = sprite.texture
				var size = tex.get_size()
				canvas.draw_set_transform(draw_pos, angle, final_scale)
				canvas.draw_texture_rect(tex, Rect2(-size * Vector2(0.5, 1.0), size), false)
			else:
				canvas.draw_set_transform(draw_pos, angle, final_scale)
				var ph_rect = Rect2(-10, -24, 20, 24)
				canvas.draw_rect(ph_rect, Color(0.0, 0.4, 0.2, 0.6))
				canvas.draw_rect(ph_rect, Color(0.0, 0.9, 0.46, 1.0), false, 1.5)
				canvas.draw_line(Vector2(-5, -17), Vector2(5, -7), Color(0.0, 0.9, 0.46, 1.0), 1.0)
				canvas.draw_line(Vector2(5, -17), Vector2(-5, -7), Color(0.0, 0.9, 0.46, 1.0), 1.0)
				
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return

	# 2. Vector line-based fallback rendering
	if blades.is_empty():
		return

	var main_color := color
	var dark_color := color.darkened(0.25).lerp(Color(0.05, 0.15, 0.08, 1.0), 0.2)
	var light_color := color.lightened(0.15).lerp(Color(0.8, 0.95, 0.4, 1.0), 0.15)
	
	var flower_colors = [
		Color(1.0, 0.92, 0.2),
		Color(1.0, 0.4, 0.5),
		Color(0.95, 0.95, 0.95)
	]

	var dark_lines := PackedVector2Array()
	var main_lines := PackedVector2Array()
	var light_lines := PackedVector2Array()

	var tips := PackedVector2Array()
	tips.resize(blades.size())

	for i in range(blades.size()):
		var blade = blades[i]
		if blade.is_foreground != render_foreground:
			continue
			
		# Calculate parallax horizontal shift
		var offset_x = (blade.base.x - cached_cam_x) * blade.parallax
			
		# Recalculate Y position locally via cached chunk points
		var actual_x = blade.base.x + offset_x
		var actual_y = blade.base.y
		if offset_x != 0.0:
			actual_y = get_local_road_height(actual_x)
			
		var draw_base = Vector2(actual_x, actual_y + blade.y_offset)
		
		# Wind sway
		var sway = sin(time * wind_speed + draw_base.x * 0.03 + blade.sway_phase) * wind_amplitude
		
		# Truck draft
		var height_mult: float = blade.scale_mult
		var draft_sway := 0.0
		if cached_has_chassis:
			var dx = draw_base.x - cached_chassis_pos_x
			if abs(dx) < 250.0:
				var factor = (250.0 - abs(dx)) / 250.0
				var smooth_factor = factor * factor
				draft_sway = clamp(cached_chassis_vel_x * 0.015 * smooth_factor, -20.0, 20.0)
				height_mult *= clamp(1.0 - abs(cached_chassis_vel_x) * 0.0006 * smooth_factor, 0.5, 1.0)
				
		var tip = draw_base + blade.up * (blade.height * height_mult) + Vector2.RIGHT * (sway + draft_sway)
		tips[i] = tip
		
		if blade.color_group == 0:
			dark_lines.append(draw_base)
			dark_lines.append(tip)
		elif blade.color_group == 1:
			main_lines.append(draw_base)
			main_lines.append(tip)
		else:
			light_lines.append(draw_base)
			light_lines.append(tip)

	if not dark_lines.is_empty():
		canvas.draw_multiline(dark_lines, dark_color, 2.0)
	if not main_lines.is_empty():
		canvas.draw_multiline(main_lines, main_color, 2.0)
	if not light_lines.is_empty():
		canvas.draw_multiline(light_lines, light_color, 2.0)

	# Draw flowers on top of blades on this layer
	for flower in flowers:
		var blade_idx: int = flower.blade_idx
		if blade_idx < blades.size():
			if blades[blade_idx].is_foreground != render_foreground:
				continue
			var flower_pos = tips[blade_idx]
			if flower_pos != Vector2.ZERO:
				var flower_color = flower_colors[flower.color_idx]
				canvas.draw_circle(flower_pos, 1.8, flower_color)
				if flower.color_idx != 0:
					canvas.draw_circle(flower_pos, 0.7, flower_colors[0])
