extends Area2D

# Physics state
var relative_vel_x := 180.0 # Moves to the right relative to truck
var velocity := Vector2.ZERO
var bottle_gravity := 160.0       # Slow motion floaty gravity
var rotation_speed := 4.0
var damage := 15.0

# State flags
var is_thrown_back := false
var is_exploding := false
var trajectory_initialized := false
var is_molotov := false

# Catch / Hold slingshot state
var is_held := false
var catch_pos := Vector2.ZERO
var drag_start := Vector2.ZERO
var pull_vector := Vector2.ZERO

# References
var chassis: RigidBody2D

func _ready() -> void:
	# Enable input pickable to get events, though we also do a global backup check
	input_pickable = true
	add_to_group("bottles")
	
	# Add accurate capsule collision shape (matches drawn bottle bounds)
	var collision = CollisionShape2D.new()
	var shape = CapsuleShape2D.new()
	shape.radius = 7.0
	shape.height = 34.0
	collision.shape = shape
	add_child(collision)
	
	# Connect collision signals
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)
	
	# Enable scanning all collision layers to guarantee detecting the truck parts
	collision_layer = 4
	collision_mask = 0xFFFFFFFF
	
	# Find player chassis
	var truck = get_node_or_null("/root/main/truck")
	if truck:
		chassis = truck.get_node_or_null("chassis")
		
	# Randomize initial rotation speed and direction
	rotation_speed = randf_range(3.0, 6.0) * (1.0 if randf() > 0.5 else -1.0)

func _exit_tree() -> void:
	# Restore normal time scale failsafe if freed while holding
	if is_held:
		Engine.time_scale = 1.0

func _physics_process(delta: float) -> void:
	if is_exploding:
		return
		
	# Compute truck's current velocity
	var truck_vel_x = 550.0
	if is_instance_valid(chassis):
		truck_vel_x = chassis.linear_velocity.x
		
	# Target trajectory calculation: runs on first frame when position is set
	if not trajectory_initialized:
		trajectory_initialized = true
		if is_instance_valid(chassis):
			# target a slightly randomized location on the truck chassis/container
			var target_offset = Vector2(randf_range(-140.0, 40.0), -15.0)
			var target_pos = chassis.global_position + target_offset
			
			# reactable slow-motion flight duration
			var flight_time = randf_range(1.9, 2.3)
			
			var dx = target_pos.x - global_position.x
			var dy = target_pos.y - global_position.y
			
			# Physics kinematics equations to solve for exact launch velocities
			relative_vel_x = dx / flight_time
			velocity.y = (dy / flight_time) - (0.5 * bottle_gravity * flight_time)
		else:
			# Static fallback values
			relative_vel_x = 180.0
			velocity.y = randf_range(-220.0, -140.0)
		
	if is_held:
		# Keep catch_pos moving forward with the truck so it stays stationary relative to the screen!
		catch_pos.x += truck_vel_x * delta
		global_position = catch_pos - pull_vector
		
		# Keep rotation static while locked/held in the air
		queue_redraw()
		return
		
	# Rotate the bottle as it flies
	rotation += rotation_speed * delta
	
	# Apply gravity
	velocity.y += bottle_gravity * delta
	
	# Update position
	# Horizontal velocity tracks the chassis + our relative horizontal speed
	global_position.x += (truck_vel_x + relative_vel_x) * delta
	global_position.y += velocity.y * delta
	
	# Spawning flame trail particles (Throttled for performance)
	if is_molotov and not is_held and Engine.get_physics_frames() % 3 == 0:
		var parent = get_parent()
		if parent:
			var flame = CPUParticles2D.new()
			flame.amount = 5
			flame.lifetime = 0.22
			flame.one_shot = true
			flame.explosiveness = 0.8
			flame.gravity = Vector2(0, -90)
			flame.scale_amount_min = 2.0
			flame.scale_amount_max = 5.0
			
			var ramp = Gradient.new()
			ramp.set_color(0, Color(1.0, 0.45, 0.0, 0.85))
			ramp.set_color(1, Color(1.0, 0.15, 0.0, 0.0))
			flame.color_ramp = ramp
			
			parent.add_child(flame)
			flame.global_position = global_position + Vector2(0, -22).rotated(rotation)
			flame.emitting = true
			
			get_tree().create_timer(0.3).timeout.connect(flame.queue_free)
	
	# Ground collision check: shatter if touching or falling below road height
	var road_node = get_node_or_null("/root/main/Road")
	if road_node:
		var ground_y = road_node.call("get_road_height", global_position.x)
		if global_position.y >= ground_y - 6.0:
			global_position.y = ground_y - 6.0
			break_bottle()
			return
	
	# Offscreen / missed cleanup
	if global_position.y > 900.0 or global_position.x < (chassis.global_position.x - 800.0 if is_instance_valid(chassis) else 0.0):
		queue_free()
		
	queue_redraw()

func _input(event: InputEvent) -> void:
	if is_exploding:
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_pos = get_global_mouse_position()
			if event.pressed:
				if not is_thrown_back and not is_held:
					# Check if clicked directly on/near the bottle (using world space)
					if global_position.distance_to(mouse_pos) < 45.0:
						is_held = true
						catch_pos = global_position
						# Record drag start in viewport space to remain screen-independent
						drag_start = get_viewport().get_mouse_position()
						pull_vector = Vector2.ZERO
						Engine.time_scale = 0.15 # Slow down time!
			else:
				if is_held:
					# Release the bottle
					Engine.time_scale = 1.0
					is_held = false
					
					var pull_len = pull_vector.length()
					if pull_len < 15.0:
						# Click and release without much drag: TAP!
						# Restore position to catch point and break
						global_position = catch_pos
						break_bottle()
					else:
						# Launch slingshot!
						is_thrown_back = true
						var launch_dir = pull_vector.normalized()
						var launch_speed = (pull_len / 120.0) * 850.0 + 200.0
						
						relative_vel_x = launch_dir.x * launch_speed
						velocity.y = launch_dir.y * launch_speed
						
						# Spin faster during throw
						rotation_speed = randf_range(12.0, 18.0) * (-1.0 if rotation_speed < 0 else 1.0)
						spawn_deflect_sparks()
						
	elif event is InputEventMouseMotion:
		if is_held:
			# Track drag delta in screen/viewport pixels to prevent movement jitter from moving camera
			var current_mouse = get_viewport().get_mouse_position()
			pull_vector = drag_start - current_mouse
			pull_vector = pull_vector.limit_length(120.0)
			
			# Physically update position pulled back
			global_position = catch_pos - pull_vector

func break_bottle() -> void:
	if is_exploding:
		return
	is_exploding = true
	
	if is_held:
		Engine.time_scale = 1.0
		is_held = false
		
	# Shatter particles
	var particles = CPUParticles2D.new()
	particles.amount = 45 if is_molotov else 26
	particles.lifetime = 0.75 if is_molotov else 0.65
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.gravity = Vector2(0, 150) if is_molotov else Vector2(0, 240)
	particles.scale_amount_min = 4.0 if is_molotov else 2.0
	particles.scale_amount_max = 8.5 if is_molotov else 5.5
	
	# Determine realistic direction based on momentum/velocity
	var truck_vel_x = 550.0
	if is_instance_valid(chassis):
		truck_vel_x = chassis.linear_velocity.x
	var current_vel = Vector2(truck_vel_x + relative_vel_x, velocity.y)
	if current_vel.length() > 50.0:
		# Flying pieces follow momentum of the bottle
		particles.direction = current_vel.normalized()
		particles.spread = 45.0 # Narrower cone
		particles.initial_velocity_min = current_vel.length() * 0.35 + 40.0
		particles.initial_velocity_max = current_vel.length() * 0.75 + 100.0
	else:
		# Static break (e.g. tapped when held)
		particles.direction = Vector2.UP
		particles.spread = 180.0
		particles.initial_velocity_min = 80.0
		particles.initial_velocity_max = 160.0
		
	var shard_color = Color(0.25, 0.65, 0.35, 0.8) if not is_thrown_back else Color(0.2, 0.75, 1.0, 0.8)
	if is_molotov:
		shard_color = Color(0.55, 0.35, 0.15, 0.85) # Brown glass shard
		
	var ramp = Gradient.new()
	if is_molotov:
		# Fiery explosion gradient (yellow to orange to smoke)
		ramp.set_color(0, Color(1.0, 0.85, 0.1, 1.0))
		ramp.set_color(1, Color(0.25, 0.25, 0.25, 0.0))
		ramp.add_point(0.22, Color(1.0, 0.3, 0.0, 1.0))
		ramp.add_point(0.65, Color(0.4, 0.4, 0.4, 0.6))
	else:
		ramp.set_color(0, shard_color)
		ramp.set_color(1, Color(shard_color.r, shard_color.g, shard_color.b, 0.0))
		
	particles.color_ramp = ramp
	
	get_parent().add_child(particles)
	particles.global_position = global_position
	particles.emitting = true
	
	# Fast scale down before deleting
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.08)
	
	await get_tree().create_timer(0.7).timeout
	particles.queue_free()
	queue_free()

func spawn_deflect_sparks() -> void:
	var particles = CPUParticles2D.new()
	particles.amount = 14
	particles.lifetime = 0.35
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.direction = Vector2.UP
	particles.spread = 60.0
	particles.gravity = Vector2(0, 100)
	particles.initial_velocity_min = 120.0
	particles.initial_velocity_max = 220.0
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	
	var ramp = Gradient.new()
	ramp.set_color(0, Color(0.25, 0.85, 1.0, 1.0))
	ramp.set_color(1, Color(0.1, 0.45, 1.0, 0.0))
	particles.color_ramp = ramp
	
	get_parent().add_child(particles)
	particles.global_position = global_position
	particles.emitting = true
	
	await get_tree().create_timer(0.4).timeout
	particles.queue_free()

func _on_body_entered(body: Node2D) -> void:
	if is_exploding or is_held:
		return
		
	# Check if the body belongs to the player's truck (chassis, container, or tyres)
	var is_truck_part = false
	if "chassis" in body.name or "container" in body.name or "tyre" in body.name or body.is_in_group("player") or (body.get_parent() and body.get_parent().name == "truck"):
		is_truck_part = true
		
	if is_truck_part:
		# When falling normally, deal damage to truck
		if not is_thrown_back:
			var truck_node = body.get_parent()
			if truck_node and not truck_node.has_method("take_damage"):
				# Traversal in case of wheels (parent of wheels is chassis/container)
				truck_node = truck_node.get_parent()
				
			if truck_node and truck_node.has_method("take_damage"):
				# Target damage should deduct exactly 10% (1 bar) or 30% (3 bars) of max health
				var max_health = truck_node.get("truck_max_health")
				if max_health == null:
					max_health = 100.0
				var scale_val = truck_node.get("damage_scale")
				if scale_val == null or scale_val == 0.0:
					scale_val = 1.0
					
				var pct = 0.3 if is_molotov else 0.1
				var target_damage = (max_health * pct) / scale_val
				truck_node.call("take_damage", target_damage)
				
				# Spawn red floating label
				var main_node = get_node_or_null("/root/main")
				if main_node:
					var floating_label = Label.new()
					floating_label.text = "-3 HP" if is_molotov else "-1 HP"
					floating_label.add_theme_font_size_override("font_size", 22)
					floating_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2))
					main_node.add_child(floating_label)
					floating_label.global_position = global_position + Vector2(-15, -25)
					
					var lbl_tween = main_node.create_tween()
					lbl_tween.tween_property(floating_label, "global_position:y", floating_label.global_position.y - 50.0, 0.7)
					lbl_tween.parallel().tween_property(floating_label, "modulate:a", 0.0, 0.7)
					lbl_tween.tween_callback(floating_label.queue_free)
		break_bottle()

func _on_area_entered(area: Area2D) -> void:
	if is_exploding or is_held:
		return
		
	# Check if it hits an enemy car
	if area.is_in_group("enemies"):
		# Prevent instant breaking when spawning from the enemy car
		if is_thrown_back or global_position.distance_to(area.global_position) > 90.0:
			if is_thrown_back:
				if area.has_method("take_damage"):
					var enemy_dmg = 90.0 if is_molotov else 30.0
					area.call("take_damage", enemy_dmg) # Deals massive damage to enemy buggy
					
					# Shorten convoy duration by 3.0 seconds (8.0 seconds for Molotov!)
					var time_reduction = 8.0 if is_molotov else 3.0
					var timer_bar = get_node_or_null("/root/main/truck/HUD/EventTimerBar")
					if timer_bar and "time_left" in timer_bar:
						timer_bar.time_left = max(0.0, timer_bar.time_left - time_reduction)
						
						# Spawn green floating time saved label
						var main_node = get_node_or_null("/root/main")
						if main_node:
							var floating_label = Label.new()
							floating_label.text = ("-" + str(time_reduction) + "s!!") if is_molotov else "-3.0s!"
							floating_label.add_theme_font_size_override("font_size", 24)
							floating_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3) if not is_molotov else Color(1.0, 0.6, 0.1))
							main_node.add_child(floating_label)
							floating_label.global_position = global_position + Vector2(-20, -30)
							
							var lbl_tween = main_node.create_tween()
							lbl_tween.tween_property(floating_label, "global_position:y", floating_label.global_position.y - 60.0, 0.8)
							lbl_tween.parallel().tween_property(floating_label, "modulate:a", 0.0, 0.8)
							lbl_tween.tween_callback(floating_label.queue_free)
			break_bottle()

func draw_dotted_line(from: Vector2, to: Vector2, color: Color, width: float, dot_spacing: float = 12.0) -> void:
	var dir = to - from
	var length = dir.length()
	if length == 0.0:
		return
	dir = dir.normalized()
	var current_dist = 0.0
	while current_dist < length:
		var p = from + dir * current_dist
		draw_circle(p, width * 0.6, color)
		current_dist += dot_spacing

func _draw() -> void:
	if is_exploding:
		return
		
	# Draw slingshot rubber bands and parabolic trajectory guide
	if is_held:
		var local_catch = to_local(catch_pos)
		var pull_len = pull_vector.length()
		
		# Draw expanding background circle from origin to bottle with low opacity
		if pull_len > 0.0:
			var circle_color = Color(1.0, 0.38, 0.15, 0.06) # Low opacity orange fill
			var border_color = Color(1.0, 0.38, 0.15, 0.18) # Low opacity orange border
			draw_circle(local_catch, pull_len, circle_color)
			draw_arc(local_catch, pull_len, 0.0, 2.0 * PI, 32, border_color, 1.2)
		
		# Draw a single dotted line for the slingshot stretch
		var band_col = Color(1.0, 0.38, 0.15, 0.85)
		draw_dotted_line(local_catch, Vector2.ZERO, band_col, 3.0, 10.0)
				
	# Draw glass trail
	if is_thrown_back:
		if is_molotov:
			# Blazing orange/yellow fire trail
			var trail_color = Color(1.0, 0.45, 0.0, 0.3)
			draw_line(Vector2.ZERO, Vector2(-25.0, 0).rotated(rotation), trail_color, 9.0)
			draw_line(Vector2.ZERO, Vector2(-15.0, 0).rotated(rotation), Color(1.0, 0.8, 0.1, 0.75), 5.5)
		else:
			# Glowing cyan trail
			var trail_color = Color(0.1, 0.8, 1.0, 0.25)
			draw_line(Vector2.ZERO, Vector2(-25.0, 0).rotated(rotation), trail_color, 8.0)
			draw_line(Vector2.ZERO, Vector2(-15.0, 0).rotated(rotation), Color(0.3, 0.9, 1.0, 0.6), 5.0)
	elif not is_held:
		if is_molotov:
			# Small flame trail for normal throw
			var trail_color = Color(1.0, 0.4, 0.0, 0.15)
			draw_line(Vector2.ZERO, Vector2(-20.0, 0).rotated(rotation), trail_color, 6.0)
		else:
			# Normal falling trail (faint white/green)
			var trail_color = Color(1.0, 1.0, 1.0, 0.12)
			draw_line(Vector2.ZERO, Vector2(-20.0, 0).rotated(rotation), trail_color, 5.0)

	# Colors for the bottle
	var glass_color = Color(0.2, 0.55, 0.3, 0.65) # Semi-translucent forest green
	var cap_color = Color(0.8, 0.1, 0.1)          # Red cap
	var label_color = Color(0.9, 0.85, 0.7)        # Vintage label
	var line_color = Color(0.1, 0.25, 0.15)        # Dark green outline
	
	if is_molotov:
		glass_color = Color(0.55, 0.35, 0.15, 0.85) # Brown bottle for Molotov
		line_color = Color(0.25, 0.15, 0.05)
		if is_thrown_back:
			glass_color = Color(1.0, 0.3, 0.05, 0.9)
			line_color = Color(1.0, 0.6, 0.1)
		elif is_held:
			glass_color = Color(0.9, 0.45, 0.15, 0.85)
			line_color = Color(0.95, 0.7, 0.2)
	else:
		if is_thrown_back:
			# Deflected glowing style
			glass_color = Color(0.15, 0.65, 0.9, 0.7)
			cap_color = Color(1.0, 0.9, 0.1)
			line_color = Color(0.15, 0.75, 1.0)
		elif is_held:
			# Glow color when aiming
			glass_color = Color(0.2, 0.75, 0.4, 0.7)
			cap_color = Color(0.95, 0.2, 0.2)
			line_color = Color(0.2, 0.9, 0.35)
		
	# Coordinates for drawing bottle centered
	# Body: box from (-6, -10) to (6, 12)
	var body_points = PackedVector2Array([
		Vector2(-6, -10),
		Vector2(6, -10),
		Vector2(6, 12),
		Vector2(-6, 12)
	])
	draw_colored_polygon(body_points, glass_color)
	draw_polyline(PackedVector2Array([Vector2(-6, -10), Vector2(6, -10), Vector2(6, 12), Vector2(-6, 12), Vector2(-6, -10)]), line_color, 1.5)
	
	# Label: box from (-5, -4) to (5, 6)
	var label_points = PackedVector2Array([
		Vector2(-5, -4),
		Vector2(5, -4),
		Vector2(5, 6),
		Vector2(-5, 6)
	])
	draw_colored_polygon(label_points, label_color)
	
	# Neck: from (-3, -10) to (3, -22)
	var neck_points = PackedVector2Array([
		Vector2(-3, -10),
		Vector2(3, -10),
		Vector2(3, -22),
		Vector2(-3, -22)
	])
	draw_colored_polygon(neck_points, glass_color)
	draw_polyline(PackedVector2Array([Vector2(-3, -10), Vector2(-3, -22), Vector2(3, -22), Vector2(3, -10)]), line_color, 1.5)
	
	# Neck cap or wick
	if not is_molotov:
		# Cap: from (-4, -22) to (4, -25)
		draw_rect(Rect2(-4, -25, 8, 3), cap_color)
		draw_rect(Rect2(-4, -25, 8, 3), line_color, false, 1.0)
	else:
		# Draw wick rag
		var wick_pts = PackedVector2Array([
			Vector2(-2, -22), Vector2(2, -22),
			Vector2(3, -27), Vector2(-3, -27)
		])
		draw_colored_polygon(wick_pts, Color(0.85, 0.8, 0.75)) # Off-white wick
		draw_polyline(wick_pts, line_color, 1.0)
		
		# Draw animated flickering flame
		var time_ms = Time.get_ticks_msec()
		var flick_w = sin(time_ms * 0.035) * 2.5
		var flick_h = cos(time_ms * 0.025) * 4.0
		
		# Outer orange flame
		var flame_pts_out = PackedVector2Array([
			Vector2(-4.5 + flick_w * 0.4, -27),
			Vector2(4.5 + flick_w * 0.4, -27),
			Vector2(flick_w, -42 - flick_h)
		])
		draw_colored_polygon(flame_pts_out, Color(1.0, 0.45, 0.0, 0.95))
		
		# Inner yellow flame
		var flame_pts_in = PackedVector2Array([
			Vector2(-2.0 + flick_w * 0.25, -27),
			Vector2(2.0 + flick_w * 0.25, -27),
			Vector2(flick_w, -37 - flick_h * 0.65)
		])
		draw_colored_polygon(flame_pts_in, Color(1.0, 0.85, 0.1, 0.95))
	
	# Shine lines
	draw_line(Vector2(-4, -8), Vector2(-4, 10), Color(1.0, 1.0, 1.0, 0.4), 1.0)
	draw_line(Vector2(-1, -20), Vector2(-1, -12), Color(1.0, 1.0, 1.0, 0.4), 0.8)
