@tool
extends RigidBody2D

var smoke_particles: CPUParticles2D
var dust_particles: CPUParticles2D

@onready var tyre_1: RigidBody2D = get_node_or_null("../tyre-1")

func _ready() -> void:
	# Hide placeholder primitive rectangles
	var head_node = get_node_or_null("head")
	if head_node:
		head_node.visible = false
	var rim_node = get_node_or_null("rim_front")
	if rim_node:
		rim_node.visible = false

	# Setup exhaust smoke particles
	smoke_particles = CPUParticles2D.new()
	smoke_particles.position = Vector2(6, -85)
	smoke_particles.amount = 25
	smoke_particles.lifetime = 1.0
	smoke_particles.preprocess = 0.5
	smoke_particles.randomness = 0.4
	smoke_particles.lifetime_randomness = 0.3
	smoke_particles.direction = Vector2(-0.8, -0.6)
	smoke_particles.spread = 20.0
	smoke_particles.gravity = Vector2(0, -60) # Smoke rises
	smoke_particles.initial_velocity_min = 25.0
	smoke_particles.initial_velocity_max = 50.0
	smoke_particles.scale_amount_min = 4.0
	smoke_particles.scale_amount_max = 12.0
	
	# Smoke scale curve (grow over time)
	var curve = Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 1.8))
	smoke_particles.scale_amount_curve = curve

	# Smoke color ramp (fade to transparent)
	var smoke_ramp = Gradient.new()
	smoke_ramp.set_color(0, Color(0.4, 0.4, 0.4, 0.5)) # Darker exhaust
	smoke_ramp.set_color(1, Color(0.7, 0.7, 0.7, 0.0))
	smoke_particles.color_ramp = smoke_ramp
	smoke_particles.local_coords = false
	add_child(smoke_particles)

	# Setup wheel dust particles
	dust_particles = CPUParticles2D.new()
	dust_particles.position = Vector2(35, 19.25)
	dust_particles.amount = 15
	dust_particles.lifetime = 0.5
	dust_particles.direction = Vector2(-1.0, -0.2)
	dust_particles.spread = 25.0
	dust_particles.gravity = Vector2(0, 150) # Fall to ground
	dust_particles.initial_velocity_min = 40.0
	dust_particles.initial_velocity_max = 90.0
	dust_particles.scale_amount_min = 2.0
	dust_particles.scale_amount_max = 5.0

	var dust_ramp = Gradient.new()
	dust_ramp.set_color(0, Color(0.65, 0.55, 0.45, 0.7)) # Dusty brown
	dust_ramp.set_color(1, Color(0.65, 0.55, 0.45, 0.0))
	dust_particles.color_ramp = dust_ramp
	dust_particles.local_coords = false
	add_child(dust_particles)
	
	# Enable contact monitoring for tyre-1 to track road contact
	if tyre_1:
		tyre_1.contact_monitor = true
		tyre_1.max_contacts_reported = max(tyre_1.max_contacts_reported, 2)

func _physics_process(_delta: float) -> void:
	queue_redraw()
	
	# Control exhaust smoke emission based on speed
	var speed = linear_velocity.length()
	if speed > 20.0:
		smoke_particles.amount = 35
		smoke_particles.initial_velocity_min = 40.0
		smoke_particles.initial_velocity_max = 80.0
	else:
		smoke_particles.amount = 15
		smoke_particles.initial_velocity_min = 20.0
		smoke_particles.initial_velocity_max = 40.0
		
	# Control tyre dust emission based on contact and speed
	var emit_dust = false
	if is_instance_valid(tyre_1) and speed > 30.0:
		if tyre_1.get_colliding_bodies().size() > 0:
			emit_dust = true
			
	dust_particles.emitting = emit_dust

func _draw() -> void:
	# Calculate engine wobble vibration
	var speed = linear_velocity.length()
	var wobble = 0.0
	if speed < 15.0:
		wobble = sin(Time.get_ticks_msec() * 0.06) * 0.7 # Engine idle vibration
	else:
		wobble = sin(Time.get_ticks_msec() * 0.03) * 0.4 # Drive vibration
	
	var wobble_offset = Vector2(0, wobble)

	# --- 1. Draw Suspension Spring ---
	if is_instance_valid(tyre_1):
		var local_tyre = to_local(tyre_1.global_position)
		draw_spring(Vector2(35, -30), local_tyre, 7.0, 5)

	# --- 2. Draw Exhaust Pipe (Behind Cabin) ---
	var exhaust_color = Color(0.6, 0.62, 0.65)
	# Main pipe vertical stack
	draw_rect(Rect2(4, -80, 4, 45), exhaust_color, true)
	# Chrome top curve
	draw_circle(Vector2(6, -80), 2.0, exhaust_color)
	# Moving exhaust flap (opens based on speed)
	var flap_angle = clamp(speed * 0.02, 0.0, 0.8)
	var flap_end = Vector2(6, -82) + Vector2(cos(flap_angle - PI/4), sin(flap_angle - PI/4)) * 6.0
	draw_line(Vector2(6, -82), flap_end, Color(0.3, 0.3, 0.3), 2.0)

	# --- 3. Draw Cabin Body (Styled wedge shape) ---
	# Coordinates shifted by wobble_offset for engine shake
	var cab_color = Color(0.95, 0.43, 0.06) # Premium bright orange/yellow
	var shadow_color = Color(0.8, 0.32, 0.03)
	
	var cab_poly = PackedVector2Array([
		Vector2(1, 0) + wobble_offset,
		Vector2(1, -72) + wobble_offset,
		Vector2(36, -72) + wobble_offset,
		Vector2(60, -42) + wobble_offset,
		Vector2(68, -42) + wobble_offset,
		Vector2(68, 0) + wobble_offset
	])
	draw_polygon(cab_poly, PackedColorArray([cab_color]))
	
	# Draw bottom metal plate / side skirts
	var plate_poly = PackedVector2Array([
		Vector2(1, -12) + wobble_offset,
		Vector2(68, -12) + wobble_offset,
		Vector2(68, 0) + wobble_offset,
		Vector2(1, 0) + wobble_offset
	])
	draw_polygon(plate_poly, PackedColorArray([Color(0.18, 0.18, 0.2)]))

	# Draw cabin side shadow band (horizontal strip)
	var shadow_poly = PackedVector2Array([
		Vector2(1, -44) + wobble_offset,
		Vector2(58, -44) + wobble_offset,
		Vector2(62, -42) + wobble_offset,
		Vector2(68, -42) + wobble_offset,
		Vector2(68, -34) + wobble_offset,
		Vector2(1, -34) + wobble_offset
	])
	draw_polygon(shadow_poly, PackedColorArray([shadow_color]))

	# --- 4. Draw Cabin Side Window (Cyan glass with reflection) ---
	var window_color = Color(0.25, 0.75, 0.9, 0.65)
	var window_poly = PackedVector2Array([
		Vector2(18, -66) + wobble_offset,
		Vector2(35, -66) + wobble_offset,
		Vector2(54, -45) + wobble_offset,
		Vector2(18, -45) + wobble_offset
	])
	draw_polygon(window_poly, PackedColorArray([window_color]))
	# Window border
	draw_polyline(window_poly, Color(0.1, 0.1, 0.1), 2.0)
	
	# Windshield white reflection glint
	var glint_poly = PackedVector2Array([
		Vector2(28, -66) + wobble_offset,
		Vector2(32, -66) + wobble_offset,
		Vector2(44, -45) + wobble_offset,
		Vector2(40, -45) + wobble_offset
	])
	draw_polygon(glint_poly, PackedColorArray([Color(1, 1, 1, 0.35)]))

	# Draw driver silhouette inside (subtle steering driver)
	draw_circle(Vector2(26, -53) + wobble_offset, 4.5, Color(0.08, 0.08, 0.1, 0.8)) # head
	draw_rect(Rect2(Vector2(22, -48) + wobble_offset, Vector2(9, 3)), Color(0.08, 0.08, 0.1, 0.8), true) # shoulders

	# --- 5. Draw Front Grille details ---
	# Grille lines (black metallic slots)
	for i in range(4):
		var y_off = -32 + (i * 5)
		draw_line(Vector2(61, y_off) + wobble_offset, Vector2(68, y_off) + wobble_offset, Color(0.1, 0.1, 0.12), 2.0)

	# Bumper
	draw_rect(Rect2(Vector2(63, -12) + wobble_offset, Vector2(5, 12)), Color(0.12, 0.12, 0.14), true)

	# --- 6. Draw Carbon Wheel Arch ---
	# Centered at (35, 0)
	var arch_center = Vector2(35, -2)
	var arch_radius = 24.5
	var arch_points = PackedVector2Array()
	var arch_steps = 16
	for i in range(arch_steps + 1):
		var angle = PI + (PI * i / arch_steps)
		arch_points.append(arch_center + Vector2(cos(angle), sin(angle)) * arch_radius)
	draw_polyline(arch_points, Color(0.12, 0.12, 0.14), 4.5)

# Helper function to draw dynamic coil springs
func draw_spring(from_pos: Vector2, to_pos: Vector2, width: float, coils: int) -> void:
	var dir = (to_pos - from_pos).normalized()
	var length = from_pos.distance_to(to_pos)
	if length < 8.0:
		return
	var perpendicular = Vector2(-dir.y, dir.x)
	
	# Draw shock absorber center shaft
	draw_line(from_pos, to_pos, Color(0.2, 0.2, 0.22), 4.0)
	draw_line(from_pos + dir * 3.0, to_pos - dir * 3.0, Color(0.65, 0.65, 0.7), 2.0)
	
	# Coil springs wrap around the shaft
	var start_spring = from_pos + dir * 6.0
	var end_spring = to_pos - dir * 6.0
	var coil_len = start_spring.distance_to(end_spring)
	
	var points = PackedVector2Array()
	points.append(from_pos)
	points.append(start_spring)
	
	var steps = coils * 2
	for i in range(steps + 1):
		var t = float(i) / steps
		var p = start_spring + dir * (t * coil_len)
		if i > 0 and i < steps:
			var offset = perpendicular * (width * (-1.0 if i % 2 == 0 else 1.0))
			points.append(p + offset)
		else:
			points.append(p)
			
	points.append(end_spring)
	points.append(to_pos)
	
	# Glowing sports suspension red color
	draw_polyline(points, Color(0.9, 0.15, 0.15), 2.8)
