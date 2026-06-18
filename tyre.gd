@tool
extends Polygon2D

@export var radius := 50:
	set(value):
		radius = value
		update_polygon()

@export var points_count := 32:
	set(value):
		points_count = max(value, 3)
		update_polygon()

func _ready():
	update_polygon()

func update_polygon():
	var points = PackedVector2Array()
	for i in points_count:
		var angle = TAU * i / points_count
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	polygon = points
	color = Color.RED