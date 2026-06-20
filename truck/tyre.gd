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

func _draw() -> void:
	# 1. Draw outer tire rubber (charcoal black)
	var tire_color = Color(0.12, 0.12, 0.14)
	draw_circle(Vector2.ZERO, radius, tire_color)
	
	# 2. Draw tread detailing around the perimeter
	var tread_color = Color(0.06, 0.06, 0.08)
	var tread_count = 12
	for i in range(tread_count):
		var angle = (TAU * i / tread_count)
		var dir = Vector2(cos(angle), sin(angle))
		draw_line(dir * (radius - 3.0), dir * radius, tread_color, 3.5)
		
	# 3. Draw inner tire wall shadow ring
	draw_circle(Vector2.ZERO, radius - 4.5, Color(0.18, 0.18, 0.20))
	
	# 4. Draw metal chrome rim
	var rim_color = Color(0.68, 0.70, 0.73)
	draw_circle(Vector2.ZERO, radius - 6.5, rim_color)
	
	# 5. Draw inner rim accent (dark carbon center)
	draw_circle(Vector2.ZERO, radius - 10.5, Color(0.24, 0.25, 0.28))
	
	# 6. Draw 5 spokes and outer holes for rotation visuals
	var spokes = 5
	for i in range(spokes):
		var angle = (TAU * i / spokes)
		var dir = Vector2(cos(angle), sin(angle))
		# Silver spokes
		draw_line(Vector2.ZERO, dir * (radius - 10.5), rim_color, 2.5)
		# Rim holes/bolts
		var bolt_pos = dir * (radius - 8.5)
		draw_circle(bolt_pos, 1.8, Color(0.1, 0.1, 0.12))
		
	# 7. Draw silver center hubcap
	draw_circle(Vector2.ZERO, 3.2, Color(0.9, 0.9, 0.95))