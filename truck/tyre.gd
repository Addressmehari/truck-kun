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

# ── Runtime state set by Truck ──
var _move_input: float = 0.0 # -1, 0, or 1 (set by truck.gd)
var _is_braking: bool = false # active brake flag
var _is_parked: bool = false # handbrake / park lock
var _boost_active: bool = false # reward velocity boost

# ── Public API called by truck.gd each physics frame ──

## Called when the truck wants to drive.
## move_input: -1.0 (reverse), 0.0 (coast), 1.0 (forward)
func drive(move_input: float, braking: bool, parked: bool, boost: bool) -> void:
	_move_input = move_input
	_is_braking = braking
	_is_parked = parked
	_boost_active = boost

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return

	if _is_parked:
		lock_rotation = true
		angular_velocity = 0.0
		return

	lock_rotation = false

	# Coast friction when no input
	if _move_input == 0.0 and not _is_braking:
		angular_velocity = lerp(angular_velocity, 0.0, 1.5 * delta)
		return

	# Active brake
	if _is_braking:
		angular_velocity = lerp(angular_velocity, 0.0, 12.0 * delta)
		return

	# Apply torque
	if _move_input != 0.0:
		apply_torque(_move_input * torque_power)

	# Cap angular velocity
	var cap = 60.0 if _boost_active else max_angular_velocity
	angular_velocity = clamp(angular_velocity, -cap, cap)

	# During boost, force full spin
	if _boost_active:
		angular_velocity = 55.0

func update_collision_shape():
	var shape_node = get_node_or_null("CollisionShape2D")
	if shape_node and shape_node.shape is CircleShape2D:
		shape_node.shape.radius = radius

func _ready():
	var shape_node = get_node_or_null("CollisionShape2D")
	if shape_node and shape_node.shape:
		shape_node.shape = shape_node.shape.duplicate()
	update_collision_shape()

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