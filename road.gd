@tool
extends StaticBody2D

@export var road_length := 15000.0:
	set(val):
		road_length = val
		generate_road()

@export var step_size := 30.0: # Distance between points on the curve (lower is smoother)
	set(val):
		step_size = max(5.0, val) # Prevent infinite loops
		generate_road()

@export var road_bottom := 800.0: # How deep the ground polygon extends
	set(val):
		road_bottom = val
		generate_road()

@export_group("Road Shape Settings")
@export var is_flat := true:
	set(val):
		is_flat = val
		generate_road()

@export var flat_height := 42.0:
	set(val):
		flat_height = val
		generate_road()

@export var hill_amplitude_multiplier := 1.0:
	set(val):
		hill_amplitude_multiplier = val
		generate_road()

# Fetch children nodes dynamically in editor (setters can run before _ready)
func _get_collision_polygon() -> CollisionPolygon2D:
	return get_node_or_null("CollisionPolygon2D")

func _get_road_fill() -> Polygon2D:
	return get_node_or_null("RoadFill")

func _get_line_2d() -> Line2D:
	return get_node_or_null("Line2D")

func _ready() -> void:
	generate_road()

# Math function defining the height of the road at any X coordinate
func get_road_height(x: float) -> float:
	if is_flat:
		return flat_height
		
	# Make a flat starting zone around the spawn area (x = 0)
	if abs(x) < 400.0:
		return 42.0
		
	# Smoothly transition from flat to hills
	var factor = clamp((abs(x) - 400.0) / 300.0, 0.0, 1.0)
	
	# Combine waves to create interesting rolling hills and dips
	var long_hills = sin(x * 0.0015) * 140.0   # Large elevations
	var medium_waves = cos(x * 0.004) * 50.0   # Medium slopes
	var small_bumps = sin(x * 0.012) * 12.0     # Small bumpy texture
	
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
