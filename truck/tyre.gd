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

# ── Driving parameters (tweakable per wheel in the Inspector) ──
@export var torque_power := 25000.0
@export var max_angular_velocity := 45.0

# ── Public API: called by truck.gd inside its own _physics_process ──
# All physics is applied immediately here so there is no race condition
# between an independent _physics_process and the caller.
#
# delta   – physics delta from truck.gd (ensures consistent timing)
# move_input – -1.0 (reverse), 0.0 (coast), 1.0 (forward)
# braking  – active brake flag
# parked   – handbrake / park lock
# boost    – reward velocity boost active
func drive(delta: float, move_input: float, braking: bool, parked: bool, boost: bool) -> void:
	if parked:
		lock_rotation = true
		angular_velocity = 0.0
		return

	lock_rotation = false

	# Coast friction – no input and not braking
	if move_input == 0.0 and not braking:
		angular_velocity = lerp(angular_velocity, 0.0, 1.5 * delta)
		return

	# Active brake – quickly bleed spin
	if braking:
		angular_velocity = lerp(angular_velocity, 0.0, 12.0 * delta)
		return

	# Apply torque to build up wheel speed
	if move_input != 0.0:
		apply_torque(move_input * torque_power)

	# Cap angular velocity
	var cap := 60.0 if boost else max_angular_velocity
	angular_velocity = clamp(angular_velocity, -cap, cap)

	# During boost, enforce full spin directly
	if boost:
		angular_velocity = 55.0

func update_collision_shape() -> void:
	var shape_node = get_node_or_null("CollisionShape2D")
	if shape_node and shape_node.shape is CircleShape2D:
		shape_node.shape.radius = radius

func _ready() -> void:
	var shape_node = get_node_or_null("CollisionShape2D")
	if shape_node and shape_node.shape:
		shape_node.shape = shape_node.shape.duplicate()
	update_collision_shape()

func _draw() -> void:
	# 1. Outer tire rubber (charcoal black)
	var tire_color = Color(0.12, 0.12, 0.14)
	draw_circle(Vector2.ZERO, radius, tire_color)

	# 2. Tread detailing around the perimeter
	var tread_color = Color(0.06, 0.06, 0.08)
	var tread_count = 12
	for i in range(tread_count):
		var angle = (TAU * i / tread_count)
		var dir = Vector2(cos(angle), sin(angle))
		draw_line(dir * (radius - 3.0), dir * radius, tread_color, 3.5)

	# 3. Inner tire wall shadow ring
	draw_circle(Vector2.ZERO, radius - 4.5, Color(0.18, 0.18, 0.20))

	# 4. Metal chrome rim
	var rim_color = Color(0.68, 0.70, 0.73)
	draw_circle(Vector2.ZERO, radius - 6.5, rim_color)

	# 5. Inner rim accent (dark carbon center)
	draw_circle(Vector2.ZERO, radius - 10.5, Color(0.24, 0.25, 0.28))

	# 6. Five spokes and outer bolt holes for rotation visuals
	var spokes = 5
	for i in range(spokes):
		var angle = (TAU * i / spokes)
		var dir = Vector2(cos(angle), sin(angle))
		draw_line(Vector2.ZERO, dir * (radius - 10.5), rim_color, 2.5)
		var bolt_pos = dir * (radius - 8.5)
		draw_circle(bolt_pos, 1.8, Color(0.1, 0.1, 0.12))

	# 7. Silver center hubcap
	draw_circle(Vector2.ZERO, 3.2, Color(0.9, 0.9, 0.95))