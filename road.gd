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

# Math function defining the height of the road at any X coordinate
func get_road_height(x: float) -> float:
	if is_flat:
		return flat_height
		
	# Make a flat starting zone around the spawn area (x = 0)
	if abs(x) < 400.0:
		return 42.0
		
	# Smoothly transition from flat to hills
	var factor = clamp((abs(x) - 400.0) / 300.0, 0.0, 1.0)
	
	# Combine waves to create interesting rolling hills and dips, offset by seed
	var long_hills = sin((x + seed_offset_1) * 0.0015) * 140.0   # Large elevations
	var medium_waves = cos((x + seed_offset_2) * 0.004) * 50.0   # Medium slopes
	var small_bumps = sin((x + seed_offset_3) * 0.012) * 12.0     # Small bumpy texture
	
	var height = 42.0 + (long_hills + medium_waves + small_bumps) * hill_amplitude_multiplier
	return lerp(42.0, height, factor)

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

func create_chunk(i: int) -> void:
	var start_x = i * chunk_width
	var end_x = (i + 1) * chunk_width
	
	var surface_points = PackedVector2Array()
	var x = start_x
	while x <= end_x:
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
	
	active_chunks[i] = {
		"collision": col_poly,
		"fill": fill,
		"line": line
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
		active_chunks.erase(i)
