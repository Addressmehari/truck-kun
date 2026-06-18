@tool
extends RigidBody2D

@export var radius := 19.25:
	set(value):
		radius = value
		queue_redraw()
		update_collision_shape()

@export var color := Color(1, 0, 0, 1):
	set(value):
		color = value
		queue_redraw()

func _ready():
	var shape_node = get_node_or_null("CollisionShape2D")
	if shape_node and shape_node.shape:
		shape_node.shape = shape_node.shape.duplicate()
	update_collision_shape()

func update_collision_shape():
	var shape_node = get_node_or_null("CollisionShape2D")
	if shape_node and shape_node.shape is CircleShape2D:
		shape_node.shape.radius = radius

func _draw():
	# Draw the filled circle representing the tyre
	var points = PackedVector2Array()
	var points_count = 32
	for i in points_count:
		var angle = TAU * i / points_count
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	draw_polygon(points, PackedColorArray([color]))
	
	# Draw spokes to visualize the wheel rotating
	var spoke_color = Color.WHITE if color == Color.BLACK or color.v < 0.4 else Color.BLACK
	draw_line(Vector2(-radius, 0), Vector2(radius, 0), spoke_color, 3.0)
	draw_line(Vector2(0, -radius), Vector2(0, radius), spoke_color, 3.0)