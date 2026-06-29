@tool
extends Area2D

# Config
var max_health := 60.0
var health := 60.0
var speed := 550.0
var target_distance := 450.0
var shoot_cooldown := 4.2
var cooldown_timer := 0.0

# References
var road: Node2D
var truck: Node2D
var chassis: Node2D

# VFX/State
var flash_timer := 0.0
var is_exploding := false

func _ready() -> void:
	if Engine.is_editor_hint():
		scale = Vector2(1.4, 1.4)
		z_index = 6
		return
		
	add_to_group("enemies")
	z_index = 6
	
	# Connect to signals
	area_entered.connect(_on_area_entered)
	
	# Setup Collision Shape if not already present
	var collision = get_node_or_null("CollisionShape2D")
	if not collision:
		collision = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = Vector2(80.0, 32.0)
		collision.shape = shape
		collision.position = Vector2(0.0, -16.0) # Rest on road surface
		add_child(collision)
	
	# Grab references
	road = get_node_or_null("/root/main/Road")
	truck = get_node_or_null("/root/main/truck")
	if truck:
		chassis = truck.get_node_or_null("chassis")
		
	# Randomize first shot cooldown so they don't sync fire
	cooldown_timer = randf_range(1.0, 2.5)
	
	# Draw scaling spawn bounce
	scale = Vector2.ZERO
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "scale", Vector2(1.4, 1.4), 0.5)

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		queue_redraw()
		return
		
	if is_exploding:
		return
		
	if not is_instance_valid(truck) or not is_instance_valid(chassis):
		# Just drive offscreen if truck dies
		position.x += speed * delta
		snap_to_road()
		return
		
	# 1. Chase logic: Move X position to keep distance behind chassis smoothly
	var player_x = chassis.global_position.x
	var target_x = player_x - target_distance
	
	var truck_vel_x = chassis.linear_velocity.x
	var dx = target_x - global_position.x
	
	# Smoothly match truck's velocity and correct distance gap to prevent jittering
	var speed_correction = clamp(dx * 4.0, -500.0, 800.0)
	position.x += (truck_vel_x + speed_correction) * delta
		
	# 2. Road follow & Slope rotation
	snap_to_road()
	
	# 3. Shoot logic
	if cooldown_timer > 0.0:
		cooldown_timer -= delta
	else:
		shoot_at_player()
		
	if flash_timer > 0.0:
		flash_timer -= delta
		modulate = Color(8.0, 8.0, 8.0) # White hitflash
	else:
		modulate = Color(1.0, 1.0, 1.0)
		
	# Throttle drawing to every second physics frame to optimize CPU rendering overhead
	if Engine.get_physics_frames() % 2 == 0:
		queue_redraw()

func snap_to_road() -> void:
	if road and road.has_method("get_road_height"):
		var ry = road.call("get_road_height", position.x)
		position.y = ry - 9.0
		
		# Find angle/slope
		var ry_front = road.call("get_road_height", position.x + 20.0)
		var ry_back = road.call("get_road_height", position.x - 20.0)
		rotation = (Vector2(40.0, ry_front - ry_back)).angle()

func shoot_at_player() -> void:
	if not is_instance_valid(chassis):
		return
		
	# Check if there is already an active bottle on screen
	var active_bottles = get_tree().get_nodes_in_group("bottles")
	if active_bottles.size() > 0:
		# Delay check by a short time to try again soon once the current bottle is gone
		cooldown_timer = randf_range(0.4, 0.8)
		return
		
	cooldown_timer = shoot_cooldown + randf_range(-0.5, 0.5)
	
	var bottle_script = load("res://obstacles/bottle.gd")
	if bottle_script:
		var bottle = Area2D.new()
		bottle.set_script(bottle_script)
		bottle.name = "GlassBottle"
		
		# Spawn position: top of the car chassis
		var spawn_pos = global_position + Vector2(0, -25).rotated(rotation)
		
		get_parent().add_child(bottle)
		bottle.global_position = spawn_pos

func take_damage(amount: float) -> void:
	if is_exploding:
		return
		
	health -= amount
	flash_timer = 0.12
	
	if health <= 0.0:
		explode()

func explode() -> void:
	is_exploding = true
	
	# Setup explosion particles
	var particles = CPUParticles2D.new()
	particles.amount = 35
	particles.lifetime = 0.75
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.direction = Vector2(0, -1)
	particles.spread = 50.0
	particles.gravity = Vector2(0, 150)
	particles.initial_velocity_min = 100.0
	particles.initial_velocity_max = 200.0
	particles.scale_amount_min = 5.0
	particles.scale_amount_max = 12.0
	
	var ramp = Gradient.new()
	ramp.set_color(0, Color(1.0, 0.8, 0.1, 1.0)) # Fire yellow
	ramp.set_color(1, Color(0.25, 0.25, 0.25, 0.0)) # Gray ash
	ramp.add_point(0.25, Color(1.0, 0.25, 0.0, 1.0)) # Red orange fire
	particles.color_ramp = ramp
	
	add_child(particles)
	particles.position = Vector2(0.0, -16.0)
	particles.emitting = true
	
	# Apply slight shake to dashboard if player is close
	if is_instance_valid(chassis):
		var dist = global_position.distance_to(chassis.global_position)
		if dist < 800.0 and truck:
			var dashboard = truck.get_node_or_null("HUD/Dashboard")
			if dashboard and "shake_intensity" in dashboard:
				dashboard.shake_intensity = 15.0
				
	# Fade out visual geometry
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	
	print("Combat: Enemy car destroyed!")
	
	await get_tree().create_timer(0.8).timeout
	queue_free()

func _on_area_entered(_area: Area2D) -> void:
	pass # Bullets handle hit checks on enemies group directly

func _draw() -> void:
	if is_exploding:
		return
		
	# If there are visible visual child nodes, bypass default vector drawing
	var has_custom_visuals := false
	for child in get_children():
		if (child is ColorRect or child is Sprite2D or child is Polygon2D) and child.visible:
			has_custom_visuals = true
			break
	if has_custom_visuals:
		return
		
	var is_silhouette := false
	if road and road.has_method("get_current_biome"):
		var biome = road.call("get_current_biome")
		if biome and biome.get("use_silhouette_truck") == true:
			is_silhouette = true
			
	# HCR Buggy theme colors
	var panel_color = Color(1.0, 0.42, 0.0) # Bright HCR Orange
	var frame_color = Color(0.12, 0.14, 0.16) # Dark roll cage
	var coil_color = Color(1.0, 0.75, 0.0) # Yellow shock springs
	var metal_color = Color(0.5, 0.52, 0.56)
	
	if is_silhouette:
		panel_color = Color.BLACK
		frame_color = Color.BLACK
		coil_color = Color.BLACK
		metal_color = Color.BLACK
		
	if flash_timer > 0.0:
		panel_color = Color(1.0, 1.0, 1.0)
		frame_color = Color(1.0, 1.0, 1.0)
		coil_color = Color(1.0, 1.0, 1.0)
		metal_color = Color(1.0, 1.0, 1.0)
		
	var metal_trim = Color(0.08, 0.09, 0.1)
	if is_silhouette:
		metal_trim = Color.BLACK
	if flash_timer > 0.0:
		metal_trim = Color(1.0, 1.0, 1.0)
	
	# Wheels config for suspension math
	var w1_pos = Vector2(-24, -5)
	var w2_pos = Vector2(24, -5)
	var wheel_spin_angle = 0.0
	if Engine.is_editor_hint():
		wheel_spin_angle = Time.get_ticks_msec() * 0.015
	else:
		wheel_spin_angle = position.x / 14.0
		
	# 2. Exposed Suspension & Coil Springs (Drawn behind body)
	for w_pos in [w1_pos, w2_pos]:
		var mount_pt = Vector2(w_pos.x * 0.5, -22.0)
		# Draw solid suspension arm
		draw_line(w_pos, mount_pt, Color(0.3, 0.32, 0.35) if flash_timer <= 0.0 else Color(1, 1, 1), 3.0)
		
		# Precalculate spring angle direction once outside the inner loop
		var spring_vector = mount_pt - w_pos
		var offset_dir = Vector2.UP.rotated(spring_vector.angle())
		
		# Draw detailed helical coil spring
		var coil_steps = 7
		for i in range(coil_steps):
			var t1 = float(i) / coil_steps
			var t2 = float(i + 1) / coil_steps
			var p1 = w_pos.lerp(mount_pt, t1)
			var p2 = w_pos.lerp(mount_pt, t2)
			# Alternate sides for spring coils
			var offset = offset_dir * (3.5 if i % 2 == 0 else -3.5)
			draw_line(p1 + offset, p2 - offset, coil_color, 2.0)
			
	# 3. Rear Exposed Engine block & Angled Exhaust
	var eng_pts = PackedVector2Array([
		Vector2(-28, -12), Vector2(-16, -12),
		Vector2(-16, -20), Vector2(-28, -20)
	])
	var eng_color = Color(0.2, 0.22, 0.25) if flash_timer <= 0.0 else Color(1, 1, 1)
	if is_silhouette and flash_timer <= 0.0:
		eng_color = Color.BLACK
	draw_colored_polygon(eng_pts, eng_color)
	draw_polyline(eng_pts, metal_trim, 1.2)
	# Engine fan/pulley detail
	draw_circle(Vector2(-22, -16), 3.0, Color.DARK_GRAY if not is_silhouette else Color.BLACK)
	
	# Exhaust sidepipe pointing up/back with backfire sparks
	var exh_start = Vector2(-24, -20)
	var exh_end = Vector2(-34, -27)
	draw_line(exh_start, exh_end, metal_color, 3.0)
	if not is_silhouette and flash_timer <= 0.0 and Engine.get_physics_frames() % 6 < 3:
		draw_line(exh_end, exh_end + Vector2(-8 - randf() * 4.0, -6), Color(1.0, 0.5, 0.1, 0.8), 2.0)
		draw_line(exh_end, exh_end + Vector2(-5 - randf() * 3.0, -3), Color(1.0, 0.8, 0.2, 0.9), 1.2)
		
	# 4. HCR-style Minimalist Body Panels (Orange)
	# Nose hood panel
	var nose_pts = PackedVector2Array([
		Vector2(14, -12), Vector2(30, -12),
		Vector2(22, -18), Vector2(14, -18)
	])
	draw_colored_polygon(nose_pts, panel_color)
	draw_polyline(nose_pts, metal_trim, 1.5)
	
	# Cabin side panel
	var side_pts = PackedVector2Array([
		Vector2(-16, -12), Vector2(14, -12),
		Vector2(6, -20), Vector2(-12, -20)
	])
	draw_colored_polygon(side_pts, panel_color)
	draw_polyline(side_pts, metal_trim, 1.5)
	
	# 5. Tubular Roll Cage Frame (Thick structural rails overlay)
	# Bottom rail
	draw_line(Vector2(-32, -12), Vector2(32, -12), frame_color, 3.5)
	# Front bumper loop
	draw_line(Vector2(32, -12), Vector2(34, -17), frame_color, 3.5)
	draw_line(Vector2(34, -17), Vector2(30, -12), frame_color, 3.5)
	# A-pillar
	draw_line(Vector2(16, -12), Vector2(4, -30), frame_color, 3.5)
	# B-pillar
	draw_line(Vector2(-14, -12), Vector2(-8, -30), frame_color, 3.5)
	# Roof bar
	draw_line(Vector2(-8, -30), Vector2(4, -30), frame_color, 3.5)
	# Rear roll bar brace
	draw_line(Vector2(-8, -30), Vector2(-30, -12), frame_color, 3.5)
	
	# 6. Oversized Heavy-Duty Chunky Wheels
	for w_pos in [w1_pos, w2_pos]:
		# Outer black tire core (radius 14.0)
		draw_circle(w_pos, 11.5, metal_trim)
		
		# 8 Aggressive off-road tread blocks (spin dynamically)
		for t in range(8):
			var angle = t * (2.0 * PI / 8.0) + wheel_spin_angle
			var tread_start = w_pos + Vector2(cos(angle), sin(angle)) * 11.0
			var tread_end = w_pos + Vector2(cos(angle), sin(angle)) * 14.0
			draw_line(tread_start, tread_end, metal_trim, 3.5)
			
		# Inner HCR matching rim hub
		draw_circle(w_pos, 7.5, panel_color)
		draw_circle(w_pos, 3.0, frame_color)
		
		# 4 Rim spokes (dynamic rotation)
		for s in range(4):
			var angle = s * (2.0 * PI / 4.0) + wheel_spin_angle
			var spoke_end = w_pos + Vector2(cos(angle), sin(angle)) * 7.5
			draw_line(w_pos, spoke_end, frame_color, 1.8)
			
	# 7. No turret pod drawn in bottle defend mode
