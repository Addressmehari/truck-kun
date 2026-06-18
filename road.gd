@tool
extends StaticBody2D

@export var road_length := 15000.0
@export var step_size := 30.0 # Distance between points on the curve (lower is smoother)
@export var road_bottom := 800.0 # How deep the ground polygon extends

@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D
@onready var road_fill: Polygon2D = $RoadFill
@onready var line_2d: Line2D = $Line2D

func _ready():
	generate_road()

# Math function defining the height of the road at any X coordinate
func get_road_height(x: float) -> float:
	# Make a flat starting zone around the spawn area (x = 0)
	if abs(x) < 400.0:
		return 42.0
		
	# Smoothly transition from flat to hills
	var factor = clamp((abs(x) - 400.0) / 300.0, 0.0, 1.0)
	
	# Combine waves to create interesting rolling hills and dips
	var long_hills = sin(x * 0.0015) * 140.0   # Large elevations
	var medium_waves = cos(x * 0.004) * 50.0   # Medium slopes
	var small_bumps = sin(x * 0.012) * 12.0     # Small bumpy texture
	
	var height = 42.0 + long_hills + medium_waves + small_bumps
	return lerp(42.0, height, factor)

func generate_road():
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
	if collision_polygon:
		collision_polygon.polygon = polygon_points
		
	# Apply to visual ground fill
	if road_fill:
		road_fill.polygon = polygon_points
		
	# Apply to visual surface line
	if line_2d:
		line_2d.points = surface_points
