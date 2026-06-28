@tool
extends RigidBody2D

var wake_particles: CPUParticles2D
var bow_particles: CPUParticles2D

var road: StaticBody2D
var is_active := false

# Flotation points in local space
var float_point_1 := Vector2(-50.0, 8.0) # Rear buoyancy point
var float_point_2 := Vector2(50.0, 8.0)  # Front buoyancy point

# Buoyancy constants
const BUOYANCY_STIFFNESS := 500.0
const BUOYANCY_DAMPING := 40.0

func _ready() -> void:
	if Engine.is_editor_hint():
		return
		
	# Get road reference
	road = get_node_or_null("/root/main/Road")

	# Setup Wake/Propeller spray particles
	wake_particles = CPUParticles2D.new()
	wake_particles.position = Vector2(-92, 16)
	wake_particles.amount = 45
	wake_particles.lifetime = 0.6
	wake_particles.preprocess = 0.2
	wake_particles.direction = Vector2(-1.0, -0.15)
	wake_particles.spread = 15.0
	wake_particles.gravity = Vector2(0, 180) # falls back down
	wake_particles.initial_velocity_min = 60.0
	wake_particles.initial_velocity_max = 130.0
	wake_particles.scale_amount_min = 3.0
	wake_particles.scale_amount_max = 8.0
	wake_particles.emitting = false
	
	var wake_ramp = Gradient.new()
	wake_ramp.set_color(0, Color(0.9, 0.95, 1.0, 0.85)) # white foamy spray
	wake_ramp.set_color(1, Color(0.9, 0.95, 1.0, 0.0))
	wake_particles.color_ramp = wake_ramp
	wake_particles.local_coords = false
	add_child(wake_particles)

	# Setup Bow splash particles
	bow_particles = CPUParticles2D.new()
	bow_particles.position = Vector2(64, 20)
	bow_particles.amount = 20
	bow_particles.lifetime = 0.4
	bow_particles.direction = Vector2(0.6, -0.8)
	bow_particles.spread = 25.0
	bow_particles.gravity = Vector2(0, 220)
	bow_particles.initial_velocity_min = 50.0
	bow_particles.initial_velocity_max = 100.0
	bow_particles.scale_amount_min = 2.0
	bow_particles.scale_amount_max = 5.5
	bow_particles.emitting = false
	bow_particles.color_ramp = wake_ramp
	bow_particles.local_coords = false
	add_child(bow_particles)

func _physics_process(delta: float) -> void:
	queue_redraw()
	
	if Engine.is_editor_hint():
		return
		
	if not is_active:
		if is_instance_valid(wake_particles):
			wake_particles.emitting = false
		if is_instance_valid(bow_particles):
			bow_particles.emitting = false
		return

	# Float physics - Buoyancy on both flotation points
	_apply_buoyancy(float_point_1, delta)
	_apply_buoyancy(float_point_2, delta)

	# Auto-upright stabilization torque (keeps boat steady and upright)
	var current_rot = global_rotation
	current_rot = fposmod(current_rot + PI, 2.0 * PI) - PI
	var stabilization_torque = -current_rot * 800.0 - angular_velocity * 120.0
	apply_torque(stabilization_torque)

	# Control particle sprays based on speed and submersion
	var speed = linear_velocity.length()
	var wake_active = false
	var bow_active = false
	
	if road and road.has_method("get_road_height"):
		var rear_water = road.call("get_road_height", to_global(float_point_1).x)
		var front_water = road.call("get_road_height", to_global(float_point_2).x)
		
		# If submerged, we emit water sprays
		if to_global(float_point_1).y > rear_water - 2.0 and speed > 15.0:
			wake_active = true
		if to_global(float_point_2).y > front_water - 2.0 and speed > 35.0:
			bow_active = true
			
	wake_particles.emitting = wake_active
	bow_particles.emitting = bow_active

func _apply_buoyancy(local_pos: Vector2, delta: float) -> void:
	if not road:
		return
		
	var global_pos = to_global(local_pos)
	var water_y = road.call("get_road_height", global_pos.x)
	
	if global_pos.y > water_y:
		# Point is underwater -> Apply spring-like upward force
		var depth = global_pos.y - water_y
		var point_vel = linear_velocity + angular_velocity * Vector2(-local_pos.y, local_pos.x)
		
		var spring_force = depth * BUOYANCY_STIFFNESS
		var damping_force = point_vel.y * BUOYANCY_DAMPING
		
		# Damping must oppose motion, so we add damping_force (positive velocity is falling, which needs more upward force)
		var upward_mag = spring_force + damping_force
		# Cap upward magnitude to prevent extreme launches
		upward_mag = clamp(upward_mag, 0.0, 1500.0)
		
		var force = Vector2(0.0, -upward_mag)
		apply_force(force, global_pos - global_position)
		
		# Apply water drag force to this flotation point (heavy immersive physics feel)
		var drag_force = -point_vel * 3.0 * depth
		drag_force = drag_force.limit_length(180.0)
		apply_force(drag_force, global_pos - global_position)

func drive(move_input: float, braking: bool) -> void:
	if not is_active:
		return
		
	# Forward/Backward propulsion force along boat axis
	if move_input != 0.0:
		var thrust_power = 1200.0
		if move_input < 0.0:
			thrust_power = 700.0 # slower reverse
		apply_central_force(global_transform.x * move_input * thrust_power)
		
		# Subtle lift torque (boat bows up when accelerating forward)
		apply_torque(move_input * 250.0)
		
	# Air pitch torque controls (tilted left/right)
	var tilt_input = 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		tilt_input -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		tilt_input += 1.0
		
	if tilt_input != 0.0:
		apply_torque(-tilt_input * 1200.0)

	# Braking
	if braking:
		# Rapidly damp velocities
		linear_velocity = linear_velocity.lerp(Vector2.ZERO, 3.5 * get_process_delta_time())
		angular_velocity = lerp(angular_velocity, 0.0, 3.5 * get_process_delta_time())

func _draw() -> void:
	# Draw a beautiful, premium Speedboat / Small Yacht Yacht vector style
	
	# --- 1. Teak Wood Deck ---
	draw_line(Vector2(-80, -24), Vector2(48, -24), Color("#c68a4c"), 8.0)
	
	# --- 2. Hull Main Body (Polar White Fiberglass) ---
	var hull_poly = PackedVector2Array([
		Vector2(-84, -24),
		Vector2(-76, 24),
		Vector2(52, 24),
		Vector2(96, -24),
		Vector2(48, -24),
		Vector2(-84, -24)
	])
	draw_polygon(hull_poly, PackedColorArray([Color("#f5f6fa")]))
	
	# --- 3. Yacht Accent Strip (Midnight Blue) ---
	var trim_poly = PackedVector2Array([
		Vector2(-80, 4),
		Vector2(-76, 16),
		Vector2(50, 16),
		Vector2(86, -20),
		Vector2(74, -20),
		Vector2(42, 10),
		Vector2(-78, 4)
	])
	draw_polygon(trim_poly, PackedColorArray([Color("#192a56")]))
	
	# --- 4. Cabin Structure & Windshield (Cyan tinted glass) ---
	var glass_poly = PackedVector2Array([
		Vector2(4, -24),
		Vector2(28, -24),
		Vector2(14, -54),
		Vector2(-14, -54),
		Vector2(4, -24)
	])
	draw_polygon(glass_poly, PackedColorArray([Color(0.2, 0.72, 0.9, 0.65)]))
	draw_polyline(glass_poly, Color("#2f3640"), 4.0)
	
	# Glass shine lines
	draw_line(Vector2(12, -48), Vector2(24, -28), Color(1, 1, 1, 0.4), 3.0)
	draw_line(Vector2(4, -48), Vector2(16, -28), Color(1, 1, 1, 0.25), 1.6)
	
	# Captain Silhouette
	draw_circle(Vector2(-2, -38), 7.0, Color("#2f3640")) # Head
	draw_rect(Rect2(-8, -30, 14, 6), Color("#2f3640"), true) # Shoulders
	
	# --- 5. Stern Chrome Railing & Antenna ---
	draw_line(Vector2(-76, -24), Vector2(-76, -64), Color("#dcdde1"), 2.4) # Antenna rod
	
	# Fluttering Red Flag
	var wave = sin(Time.get_ticks_msec() * 0.02) * 5.0
	var flag_poly = PackedVector2Array([
		Vector2(-76, -64),
		Vector2(-96, -58 + wave),
		Vector2(-76, -52)
	])
	draw_polygon(flag_poly, PackedColorArray([Color("#e84118")]))
	
	# Outboard Motor / Propeller
	draw_rect(Rect2(-92, -8, 12, 28), Color("#353b48"), true)
	
	# Propeller blade blur
	var prop_speed = 0.05 * (1.0 + linear_velocity.length() * 0.1)
	var prop_y = sin(Time.get_ticks_msec() * prop_speed) * 13.0
	draw_line(Vector2(-92, 12), Vector2(-92, 12 + prop_y), Color("#dcdde1"), 4.0)
