extends RigidBody2D
class_name OpponentCar

# ── Driving & AI parameters ──
var torque_power := 35000.0
var max_angular_velocity := 50.0
var air_tilt_power := 6000.0

# ── Suspension parameters ──
var suspension_rest_dist := 10.0
var suspension_stiffness := 150.0
var suspension_damping := 8.0

# ── References ──
var tyre_back: RigidBody2D
var tyre_mid: RigidBody2D
var tyre_front: RigidBody2D
var road: Node2D
var player_chassis: RigidBody2D

# ── State / VFX ──
var is_active := false
var elapsed := 0.0

func _ready() -> void:
	# Configure RigidBody2D properties to match player truck parameters
	mass = 1.5
	center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector2(-25.0, -25.0) # Balanced center of mass
	can_sleep = false
	z_index = -1
	collision_layer = 2
	collision_mask = 2
	modulate.a = 0.8 # Reduce opacity of the opponent truck slightly
	
	# Low friction physics material for smooth sliding
	var phys_mat = PhysicsMaterial.new()
	phys_mat.friction = 0.15
	phys_mat.bounce = 0.05
	physics_material_override = phys_mat

	# 1. Setup Combined Truck Collision Polygon (Cabin + Container)
	var col_poly = CollisionPolygon2D.new()
	col_poly.polygon = PackedVector2Array([
		Vector2(-117, -2),
		Vector2(-117, -80),
		Vector2(-5, -80),
		Vector2(1, -72),
		Vector2(36, -72),
		Vector2(60, -42),
		Vector2(68, -42),
		Vector2(68, -2)
	])
	add_child(col_poly)

	# 2. Instantiate 3 Tyres dynamically at player's offsets (35, -31, -91)
	var tyre_scene = load("res://truck/tyre.tscn")
	if tyre_scene:
		# tyre_back (X = -91)
		tyre_back = tyre_scene.instantiate()
		tyre_back.name = "tyre_back"
		tyre_back.position = Vector2(-91, 10)
		tyre_back.mass = 2.0
		tyre_back.torque_power = torque_power
		tyre_back.max_angular_velocity = max_angular_velocity
		tyre_back.contact_monitor = true
		tyre_back.max_contacts_reported = 2
		tyre_back.collision_layer = 2
		tyre_back.collision_mask = 2
		add_child(tyre_back)

		# Back Groove Joint
		var gj_back = GrooveJoint2D.new()
		gj_back.name = "gj_back"
		gj_back.position = Vector2(-91, 0)
		gj_back.length = 20.0
		gj_back.initial_offset = 10.0
		add_child(gj_back)
		gj_back.node_a = gj_back.get_path_to(self)
		gj_back.node_b = gj_back.get_path_to(tyre_back)

		# tyre_mid (X = -31)
		tyre_mid = tyre_scene.instantiate()
		tyre_mid.name = "tyre_mid"
		tyre_mid.position = Vector2(-31, 10)
		tyre_mid.mass = 2.0
		tyre_mid.torque_power = torque_power
		tyre_mid.max_angular_velocity = max_angular_velocity
		tyre_mid.contact_monitor = true
		tyre_mid.max_contacts_reported = 2
		tyre_mid.collision_layer = 2
		tyre_mid.collision_mask = 2
		add_child(tyre_mid)

		# Middle Groove Joint
		var gj_mid = GrooveJoint2D.new()
		gj_mid.name = "gj_mid"
		gj_mid.position = Vector2(-31, 0)
		gj_mid.length = 20.0
		gj_mid.initial_offset = 10.0
		add_child(gj_mid)
		gj_mid.node_a = gj_mid.get_path_to(self)
		gj_mid.node_b = gj_mid.get_path_to(tyre_mid)

		# tyre_front (X = 35)
		tyre_front = tyre_scene.instantiate()
		tyre_front.name = "tyre_front"
		tyre_front.position = Vector2(35, 10)
		tyre_front.mass = 2.0
		tyre_front.torque_power = torque_power
		tyre_front.max_angular_velocity = max_angular_velocity
		tyre_front.contact_monitor = true
		tyre_front.max_contacts_reported = 2
		tyre_front.collision_layer = 2
		tyre_front.collision_mask = 2
		add_child(tyre_front)

		# Front Groove Joint
		var gj_front = GrooveJoint2D.new()
		gj_front.name = "gj_front"
		gj_front.position = Vector2(35, 0)
		gj_front.length = 20.0
		gj_front.initial_offset = 10.0
		add_child(gj_front)
		gj_front.node_a = gj_front.get_path_to(self)
		gj_front.node_b = gj_front.get_path_to(tyre_front)

	# Grab global references
	road = get_node_or_null("/root/main/Road")
	var truck = get_node_or_null("/root/main/truck")
	if truck:
		player_chassis = truck.get_node_or_null("chassis")

func _physics_process(delta: float) -> void:
	elapsed += delta
	queue_redraw()
	
	# Process suspension forces for all 3 tyres
	if is_instance_valid(tyre_back):
		_process_custom_suspension(tyre_back, Vector2(-91, -8), delta)
	if is_instance_valid(tyre_mid):
		_process_custom_suspension(tyre_mid, Vector2(-31, -8), delta)
	if is_instance_valid(tyre_front):
		_process_custom_suspension(tyre_front, Vector2(35, -8), delta)
		
	# Synchronize wheel spin (locked differential simulation)
	if is_instance_valid(tyre_back) and is_instance_valid(tyre_mid) and is_instance_valid(tyre_front):
		var avg_spin = (tyre_back.angular_velocity + tyre_mid.angular_velocity + tyre_front.angular_velocity) / 3.0
		tyre_back.angular_velocity = avg_spin
		tyre_mid.angular_velocity = avg_spin
		tyre_front.angular_velocity = avg_spin

	if not is_active:
		# Lock wheels/park before race start
		if is_instance_valid(tyre_back):
			tyre_back.drive(delta, 0.0, true, true, false)
		if is_instance_valid(tyre_mid):
			tyre_mid.drive(delta, 0.0, true, true, false)
		if is_instance_valid(tyre_front):
			tyre_front.drive(delta, 0.0, true, true, false)
		return

	# ── AI Brain Driving Input ──
	var move_input = 1.0 # Forward pedal
	var is_braking = false

	# Detect if finish line is crossed
	var target_x = -1.0
	if road:
		if road.get("delivery_target_chunk") != -1:
			var target_chunk = road.get("delivery_target_chunk")
			target_x = (target_chunk + 0.5) * road.get("chunk_width")
		elif road.get("racing_target_chunk") != -1:
			var target_chunk = road.get("racing_target_chunk")
			target_x = (target_chunk + 0.5) * road.get("chunk_width")
	
	var has_finished = target_x > 0.0 and global_position.x >= target_x
	if has_finished:
		move_input = 0.0
		is_braking = true
		if road and not road.get("opponent_finished"):
			road.set("opponent_finished", true)
			print("[OpponentCar] Opponent crossed finish line first!")

	# Detect if grounded
	var back_grounded = is_instance_valid(tyre_back) and tyre_back.get_colliding_bodies().size() > 0
	var mid_grounded = is_instance_valid(tyre_mid) and tyre_mid.get_colliding_bodies().size() > 0
	var front_grounded = is_instance_valid(tyre_front) and tyre_front.get_colliding_bodies().size() > 0
	var is_grounded = back_grounded or mid_grounded or front_grounded

	# Adaptive speed scaling (rubber-banding)
	var current_max_vel = max_angular_velocity
	if is_instance_valid(player_chassis):
		var dist_x = global_position.x - player_chassis.global_position.x
		if dist_x < -250.0:
			current_max_vel = max_angular_velocity * 1.25 # Catch-up boost
		elif dist_x > 250.0:
			current_max_vel = max_angular_velocity * 0.85 # Throttled back

	# Drive wheels
	if is_instance_valid(tyre_back):
		tyre_back.drive(delta, move_input, is_braking, false, false)
		tyre_back.angular_velocity = clamp(tyre_back.angular_velocity, -current_max_vel, current_max_vel)
	if is_instance_valid(tyre_mid):
		tyre_mid.drive(delta, move_input, is_braking, false, false)
		tyre_mid.angular_velocity = clamp(tyre_mid.angular_velocity, -current_max_vel, current_max_vel)
	if is_instance_valid(tyre_front):
		tyre_front.drive(delta, move_input, is_braking, false, false)
		tyre_front.angular_velocity = clamp(tyre_front.angular_velocity, -current_max_vel, current_max_vel)

	# 2. Mid-air leveling (stabilize cabin and cargo)
	if not is_grounded:
		var target_angle = linear_velocity.angle()
		target_angle = clamp(target_angle, -0.6, 0.6)
		var angle_error = target_angle - rotation
		apply_torque(angle_error * air_tilt_power)

func _process_custom_suspension(tyre: RigidBody2D, anchor_local: Vector2, delta: float) -> void:
	if not is_instance_valid(tyre): return
	var anchor_global = to_global(anchor_local)
	var tyre_global = tyre.global_position
	
	var up_dir = - global_transform.y
	var offset = tyre_global - anchor_global
	
	var r_chassis = anchor_global - global_position
	var v_chassis_anchor = linear_velocity + Vector2(-angular_velocity * r_chassis.y, angular_velocity * r_chassis.x)
	var rel_vel = tyre.linear_velocity - v_chassis_anchor
	
	var vert_dist = offset.dot(-up_dir)
	var vert_vel = rel_vel.dot(-up_dir)
	var vert_error = vert_dist - suspension_rest_dist
	
	var vert_force_mag = - (vert_error * suspension_stiffness) - (vert_vel * suspension_damping)
	var vert_force = - up_dir * vert_force_mag
	
	tyre.apply_central_force(vert_force)
	apply_force(-vert_force, r_chassis)

func start_race() -> void:
	is_active = true
	apply_central_impulse(Vector2(100.0, -30.0))

func _draw() -> void:
	# Stylized Cyberpunk Grey & Neon Pink styling
	var chassis_color = Color("#1e1e24") # Dark graphite
	var plate_color = Color("#0c0c0e") # Deep charcoal trim
	var window_color = Color(0.15, 0.65, 0.8, 0.5) # Translucent cyan glass
	var neon_pink = Color("#ff007f") # Electric pink accents
	var neon_cyan = Color("#00f0ff") # Electric cyan highlight
	var metal_color = Color("#6c7280")

	# 1. Exposed suspension springs (drawn behind body)
	if is_instance_valid(tyre_back):
		_draw_spring(Vector2(-91, -8), tyre_back.position, 5.0, 4, neon_pink)
	if is_instance_valid(tyre_mid):
		_draw_spring(Vector2(-31, -8), tyre_mid.position, 5.0, 4, neon_pink)
	if is_instance_valid(tyre_front):
		_draw_spring(Vector2(35, -8), tyre_front.position, 5.0, 4, neon_pink)

	# 2. Draw Exhaust Pipe
	draw_rect(Rect2(4, -80, 4, 45), metal_color, true)
	draw_circle(Vector2(6, -80), 2.0, metal_color)
	if is_active and Engine.get_physics_frames() % 6 < 3:
		# Backfire sparks at top of chimney
		draw_line(Vector2(6, -82), Vector2(6 - randf() * 8.0, -88 - randf() * 6), neon_pink, 2.0)
		draw_line(Vector2(6, -82), Vector2(8 + randf() * 4.0, -85 - randf() * 3), neon_cyan, 1.2)

	# 3. Draw Cabin Body (matching player's shape)
	var cab_poly = PackedVector2Array([
		Vector2(1, 0),
		Vector2(1, -72),
		Vector2(36, -72),
		Vector2(60, -42),
		Vector2(68, -42),
		Vector2(68, 0)
	])
	draw_polygon(cab_poly, [chassis_color])
	draw_polyline(cab_poly, neon_pink, 1.8)

	# Draw side window & frame
	var window_poly = PackedVector2Array([
		Vector2(18, -66),
		Vector2(35, -66),
		Vector2(54, -45),
		Vector2(18, -45)
	])
	draw_polygon(window_poly, [window_color])
	draw_polyline(window_poly, neon_cyan, 1.5)

	# Headlight and front grille slots
	for i in range(4):
		var y_off = -32 + (i * 5)
		draw_line(Vector2(61, y_off), Vector2(68, y_off), plate_color, 2.0)
	
	# Bumper
	draw_rect(Rect2(Vector2(63, -12), Vector2(5, 12)), plate_color, true)

	# 4. Draw Container (matching player's shape)
	var container_left = -117.0
	var container_right = -5.0
	var container_top = -80.0
	var container_bottom = -1.0
	
	draw_rect(Rect2(container_left, container_top, 112.0, 79.0), Color("#272730"), true) # Container fill
	
	# Draw Corrugated Steel ridges (Neon pink highlights)
	var rib_w = 6.0
	var rib_gap = 5.0
	var current_x = container_left + 6.0
	while current_x + rib_w < container_right:
		draw_rect(Rect2(current_x, container_top + 3.0, rib_w, 73.0), plate_color, true)
		draw_rect(Rect2(current_x + 2.0, container_top + 3.0, rib_w - 2.0, 73.0), Color("#3e3e4a"), true)
		current_x += rib_w + rib_gap

	# Warning Hazard Stripes (Neon Pink & Dark Black)
	draw_rect(Rect2(container_left + 3.0, container_bottom - 11.0, 106.0, 8.0), neon_pink, true)
	var stripe_x = container_left + 6.0
	while stripe_x < container_right - 6.0:
		draw_line(Vector2(stripe_x, container_bottom - 11.0), Vector2(stripe_x + 6.0, container_bottom - 3.0), plate_color, 3.0)
		stripe_x += 12.0

	# Container outer frame outline
	draw_rect(Rect2(container_left, container_top, 112.0, 79.0), plate_color, false, 2.5)

	# 5. Mudflap behind rear wheel
	draw_rect(Rect2(-114, 0, 3, 14), plate_color, true)
	draw_circle(Vector2(-112.5, 11), 1.0, neon_pink) # neon pink reflector

	# 6. Carbon wheel arches for all 3 wheels
	for arch_x in [35.0, -33.0, -93.0]:
		var arch_center = Vector2(arch_x, -2.0)
		var arch_radius = 24.5
		var arch_points = PackedVector2Array()
		var arch_steps = 16
		for i in range(arch_steps + 1):
			var angle = PI + (PI * i / arch_steps)
			arch_points.append(arch_center + Vector2(cos(angle), sin(angle)) * arch_radius)
		draw_polyline(arch_points, plate_color, 4.5)

	# 7. Driver outline inside cabin
	draw_circle(Vector2(26, -53), 4.5, Color.WHITE) # Helmet
	draw_rect(Rect2(Vector2(22, -48), Vector2(9, 3)), Color.WHITE, true)
	draw_rect(Rect2(Vector2(27, -54), Vector2(4, 3)), neon_cyan, true) # neon visor

func _draw_spring(from_pos: Vector2, to_pos: Vector2, width: float, coils: int, color: Color) -> void:
	var dir = (to_pos - from_pos).normalized()
	var length = from_pos.distance_to(to_pos)
	if length < 8.0:
		return
	var perpendicular = Vector2(-dir.y, dir.x)
	
	# Draw shock absorber center shaft
	draw_line(from_pos, to_pos, Color(0.1, 0.1, 0.12), 4.0)
	draw_line(from_pos + dir * 3.0, to_pos - dir * 3.0, Color(0.5, 0.52, 0.55), 2.0)
	
	var start_spring = from_pos + dir * 5.0
	var end_spring = to_pos - dir * 5.0
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
	
	draw_polyline(points, color, 2.5)
