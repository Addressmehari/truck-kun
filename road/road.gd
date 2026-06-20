@tool
extends StaticBody2D

@export var road_length := 15000.0:
	set(val):
		road_length = val
		if Engine.is_editor_hint():
			generate_road()

@export var step_size := 30.0: # Distance between points on the curve (lower is smoother)
	set(val):
		step_size = max(5.0, val) # Prevent infinite loops
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export var road_bottom := 800.0: # How deep the ground polygon extends
	set(val):
		road_bottom = val
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export_group("Road Shape Settings")
@export var is_flat := true:
	set(val):
		is_flat = val
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export var flat_height := 42.0:
	set(val):
		flat_height = val
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export var hill_amplitude_multiplier := 1.0:
	set(val):
		hill_amplitude_multiplier = val
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export var road_seed := 12345:
	set(val):
		road_seed = val
		update_seed_offsets()
		if Engine.is_editor_hint():
			generate_road()
		else:
			regenerate_runtime_chunks()

@export var chunk_width := 3000.0:
	set(val):
		chunk_width = max(500.0, val)
		if not Engine.is_editor_hint():
			regenerate_runtime_chunks()

@export var view_distance := 9000.0:
	set(val):
		view_distance = max(1000.0, val)
		if not Engine.is_editor_hint():
			regenerate_runtime_chunks()

# Seed offsets for waves
var seed_offset_1 := 0.0
var seed_offset_2 := 0.0
var seed_offset_3 := 0.0

# Dictionary to track runtime active chunks: { chunk_index: { "collision": Col, "fill": Fill, "line": Line } }
var active_chunks := {}

const TUNNEL_MIN_SPACING := 6000.0


# Captured styles for runtime chunk styling
var template_fill_color := Color(0.12, 0.12, 0.14, 1)
var template_line_width := 8.0
var template_line_color := Color(0, 0.9, 0.46, 1)

# Fetch children nodes dynamically in editor (setters can run before _ready)
func _get_collision_polygon() -> CollisionPolygon2D:
	return get_node_or_null("CollisionPolygon2D")

func _get_road_fill() -> Polygon2D:
	return get_node_or_null("RoadFill")

func _get_line_2d() -> Line2D:
	return get_node_or_null("Line2D")

func update_seed_offsets() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = road_seed
	seed_offset_1 = rng.randf_range(-10000.0, 10000.0)
	seed_offset_2 = rng.randf_range(-10000.0, 10000.0)
	seed_offset_3 = rng.randf_range(-10000.0, 10000.0)

func capture_templates() -> void:
	var fill = _get_road_fill()
	if fill:
		template_fill_color = fill.color
	var line = _get_line_2d()
	if line:
		template_line_width = line.width
		template_line_color = line.default_color

func _ready() -> void:
	update_seed_offsets()
	if Engine.is_editor_hint():
		generate_road()
	else:
		capture_templates()
		
		# Free template nodes at runtime to avoid collision/visual duplication at the start
		var col_poly = _get_collision_polygon()
		var fill = _get_road_fill()
		var line = _get_line_2d()
		if col_poly: col_poly.queue_free()
		if fill: fill.queue_free()
		if line: line.queue_free()
		
		# Initial chunk generation
		update_chunks(get_target_x())

# Base math function defining the height of the road without flattening
func get_base_road_height(x: float) -> float:
	if is_flat:
		return flat_height
		
	# Make a flat starting zone around the spawn area (x = 0)
	if abs(x) < 400.0:
		return 42.0
		
	# Smoothly transition from flat to hills using a smooth S-curve
	var raw_factor = clamp((abs(x) - 400.0) / 300.0, 0.0, 1.0)
	var factor = raw_factor * raw_factor * (3.0 - 2.0 * raw_factor)
	
	# Combine waves to create interesting rolling hills and dips, offset by seed
	var long_hills = sin((x + seed_offset_1) * 0.0015) * 140.0   # Large elevations
	var medium_waves = cos((x + seed_offset_2) * 0.004) * 50.0   # Medium slopes
	var small_bumps = sin((x + seed_offset_3) * 0.012) * 12.0     # Small bumpy texture
	
	var height = 42.0 + (long_hills + medium_waves + small_bumps) * hill_amplitude_multiplier
	return lerp(42.0, height, factor)

# Deterministically get tunnel details for a given chunk
func get_tunnel_at_chunk(chunk_index: int) -> Dictionary:
	# Avoid tunnels too close to spawn (within 1500 units)
	var spawn_buffer_chunks = int(ceil(1500.0 / chunk_width))
	if abs(chunk_index) <= spawn_buffer_chunks:
		return {}
		
	# Enforce spacing: tunnels can only spawn at chunk indices that respect the minimum physical spacing
	var spacing_chunks = int(ceil(TUNNEL_MIN_SPACING / chunk_width))
	if abs(chunk_index) % spacing_chunks != 0:
		return {}
		
	var rng = RandomNumberGenerator.new()
	# Deterministic seed per chunk
	rng.seed = hash(str(road_seed) + "_tunnel_" + str(chunk_index))
	
	# 40% chance to spawn a tunnel in this valid chunk
	if rng.randf() < 0.4:
		# Tunnel is centered in the middle of the chunk
		var tunnel_x = (chunk_index + 0.5) * chunk_width
		var base_y = get_base_road_height(tunnel_x)
		
		return {
			"x": tunnel_x,
			"y": base_y,
			"width": 1000.0,
			"height": 320.0
		}
	return {}

# Math function defining the height of the road at any X coordinate, flattened inside tunnels and paddings, smoothed in transitions
func get_road_height(x: float) -> float:
	# Determine range of chunk indices that can physically influence the height at x
	var max_influence = 1500.0 # 500 (half width) + 200 (padding) + 800 (transition)
	var min_chunk_idx = int(floor((x - max_influence) / chunk_width))
	var max_chunk_idx = int(floor((x + max_influence) / chunk_width))
	
	for check_idx in range(min_chunk_idx, max_chunk_idx + 1):
		var tunnel = get_tunnel_at_chunk(check_idx)
		if not tunnel.is_empty():
			var tunnel_x = tunnel["x"]
			var tunnel_y = tunnel["y"]
			var half_width = tunnel["width"] / 2.0
			var padding = 200.0 # 10 meters padding on front and back (1m = 20px)
			
			var flat_start = tunnel_x - half_width - padding
			var flat_end = tunnel_x + half_width + padding
			var transition_dist = 800.0
			
			var dist = x - tunnel_x
			if abs(dist) <= half_width + padding:
				return tunnel_y
			elif dist < 0 and dist >= -(half_width + padding + transition_dist):
				# Incoming transition (left side)
				var t = (x - (flat_start - transition_dist)) / transition_dist
				var smooth_t = t * t * (3.0 - 2.0 * t) # smoothstep S-curve
				return lerp(get_base_road_height(x), tunnel_y, smooth_t)
			elif dist > 0 and dist <= (half_width + padding + transition_dist):
				# Outgoing transition (right side)
				var t = (x - flat_end) / transition_dist
				var smooth_t = t * t * (3.0 - 2.0 * t) # smoothstep S-curve
				return lerp(tunnel_y, get_base_road_height(x), smooth_t)
				
	return get_base_road_height(x)

func generate_road() -> void:
	var col_poly = _get_collision_polygon()
	var fill = _get_road_fill()
	var line = _get_line_2d()
	
	if not col_poly or not fill or not line:
		return
		
	var surface_points = PackedVector2Array()
	
	# Generate points along the road surface
	var start_x = -1200.0
	var end_x = road_length
	
	var x = start_x
	while x <= end_x:
		var y = get_road_height(x)
		surface_points.append(Vector2(x, y))
		x += step_size
		
	# Ensure the last point is exactly at the end
	surface_points.append(Vector2(end_x, get_road_height(end_x)))
	
	# Create a closed polygon for the ground fill and collision
	var polygon_points = PackedVector2Array(surface_points)
	polygon_points.append(Vector2(end_x, road_bottom))
	polygon_points.append(Vector2(start_x, road_bottom))
	
	# Apply to collision shape
	col_poly.polygon = polygon_points
		
	# Apply to visual ground fill
	fill.polygon = polygon_points
		
	# Apply to visual surface line
	line.points = surface_points
	
	# If running in editor, notify dependent components like elevator systems to snap
	if Engine.is_editor_hint():
		for child in get_parent().get_children():
			if child.has_method("snap_to_road"):
				child.call("snap_to_road")

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	update_chunks(get_target_x())

func get_target_x() -> float:
	if is_inside_tree():
		var viewport = get_viewport()
		if viewport:
			var camera = viewport.get_camera_2d()
			if camera and is_instance_valid(camera):
				return camera.global_position.x
		
	var chassis = get_node_or_null("../truck/chassis")
	if chassis and is_instance_valid(chassis):
		return chassis.global_position.x
		
	return 0.0

func regenerate_runtime_chunks() -> void:
	if not Engine.is_editor_hint():
		for key in active_chunks.keys():
			destroy_chunk(key)
		update_chunks(get_target_x())

func update_chunks(player_x: float) -> void:
	var start_chunk = int(floor((player_x - view_distance) / chunk_width))
	var end_chunk = int(ceil((player_x + view_distance) / chunk_width))
	
	# Create new chunks
	for i in range(start_chunk, end_chunk + 1):
		if not active_chunks.has(i):
			create_chunk(i)
			
	# Remove old chunks
	var active_keys = active_chunks.keys()
	for i in active_keys:
		if i < start_chunk or i > end_chunk:
			destroy_chunk(i)

func spawn_tunnel_node(chunk_index: int, tunnel_data: Dictionary) -> Node2D:
	var tunnel_scene = load("res://road/tunnel.tscn")
	if not tunnel_scene:
		return null
	var tunnel = tunnel_scene.instantiate() as Node2D
	tunnel.position = Vector2(tunnel_data["x"], tunnel_data["y"])
	add_child(tunnel)
	return tunnel


func create_chunk(i: int) -> void:
	var start_x = i * chunk_width
	var end_x = (i + 1) * chunk_width
	
	var surface_points = PackedVector2Array()
	var x = start_x
	while x < end_x:
		var y = get_road_height(x)
		surface_points.append(Vector2(x, y))
		x += step_size
		
	# Ensure the last point is exactly at the end
	surface_points.append(Vector2(end_x, get_road_height(end_x)))
	
	# Create the closed polygon
	var polygon_points = PackedVector2Array(surface_points)
	polygon_points.append(Vector2(end_x, road_bottom))
	polygon_points.append(Vector2(start_x, road_bottom))
	
	# Create CollisionPolygon2D
	var col_poly = CollisionPolygon2D.new()
	col_poly.polygon = polygon_points
	add_child(col_poly)
	
	# Create Polygon2D
	var fill = Polygon2D.new()
	fill.polygon = polygon_points
	fill.color = template_fill_color
	add_child(fill)
	
	# Create Line2D
	var line = Line2D.new()
	line.points = surface_points
	line.width = template_line_width
	line.default_color = template_line_color
	add_child(line)
	
	# Spawn tunnel if present
	var tunnel_node = null
	var tunnel_data = get_tunnel_at_chunk(i)
	if not tunnel_data.is_empty():
		tunnel_node = spawn_tunnel_node(i, tunnel_data)
		
	active_chunks[i] = {
		"collision": col_poly,
		"fill": fill,
		"line": line,
		"tunnel": tunnel_node
	}

func destroy_chunk(i: int) -> void:
	if active_chunks.has(i):
		var chunk = active_chunks[i]
		if is_instance_valid(chunk.collision):
			chunk.collision.queue_free()
		if is_instance_valid(chunk.fill):
			chunk.fill.queue_free()
		if is_instance_valid(chunk.line):
			chunk.line.queue_free()
		if "tunnel" in chunk and is_instance_valid(chunk.tunnel):
			chunk.tunnel.queue_free()
		active_chunks.erase(i)
