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
	
	# Find player chassis
	var truck = get_node_or_null("/root/main/truck")
	if truck:
		chassis = truck.get_node_or_null("chassis")
		
	# Randomize initial rotation speed and direction
	rotation_speed = randf_range(3.0, 6.0) * (1.0 if randf() > 0.5 else -1.0)
	
	# Float upward initial push
	velocity.y = randf_range(-220.0, -140.0)

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
		
	if is_held:
		# Keep catch_pos moving forward with the truck so it stays stationary relative to the screen!
		catch_pos.x += truck_vel_x * delta
		global_position = catch_pos - pull_vector
		
		# Spin normally even when time is slowed down (compensate delta)
		rotation += rotation_speed * delta * (1.0 / Engine.time_scale)
		queue_redraw()
		return
		
	# Rotate the bottle as it flies
	rotation += rotation_speed * delta
	
	# Apply gravity
	velocity.y += bottle_gravity * delta
	
	# Apply air drag to relative horizontal speed when not deflected yet
	if not is_thrown_back:
		relative_vel_x = lerp(relative_vel_x, 90.0, 0.5 * delta)
	
	# Update position
	# Horizontal velocity tracks the chassis + our relative horizontal speed
	global_position.x += (truck_vel_x + relative_vel_x) * delta
	global_position.y += velocity.y * delta
	
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
	particles.amount = 26
	particles.lifetime = 0.65
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.gravity = Vector2(0, 240)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 5.5
	
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
	var ramp = Gradient.new()
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
	# When falling normal, check if it hits truck chassis/container
	if not is_thrown_back:
		if body.name == "chassis" or body.name == "container_body":
			var truck_node = body.get_parent()
			if truck_node and truck_node.has_method("take_damage"):
				truck_node.call("take_damage", damage)
				
				# Spawn red floating label
				var main_node = get_node_or_null("/root/main")
				if main_node:
					var floating_label = Label.new()
					floating_label.text = "-15 HP"
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
	# When thrown back, check if it hits an enemy car
	if is_thrown_back:
		if area.is_in_group("enemies"):
			if area.has_method("take_damage"):
				area.call("take_damage", 30.0) # Deals 30 damage to enemy buggy
				
				# Shorten convoy duration by 3.0 seconds
				var timer_bar = get_node_or_null("/root/main/truck/HUD/EventTimerBar")
				if timer_bar and "time_left" in timer_bar:
					timer_bar.time_left = max(0.0, timer_bar.time_left - 3.0)
					
					# Spawn green floating time saved label
					var main_node = get_node_or_null("/root/main")
					if main_node:
						var floating_label = Label.new()
						floating_label.text = "-3.0s!"
						floating_label.add_theme_font_size_override("font_size", 24)
						floating_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3))
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
		
		# Draw a single dotted line for the slingshot stretch
		var band_col = Color(1.0, 0.38, 0.15, 0.85)
		draw_dotted_line(local_catch, Vector2.ZERO, band_col, 3.0, 10.0)
		
		# Draw parabolic trajectory dots in aimed direction
		var pull_len = pull_vector.length()
		if pull_len >= 15.0:
			var launch_dir = pull_vector.normalized()
			var launch_speed = (pull_len / 120.0) * 850.0 + 200.0
			var launch_velocity = launch_dir * launch_speed
			
			var steps = 10
			var time_step = 0.08
			for i in range(1, steps + 1):
				var time = i * time_step
				var dot_pos = Vector2(
					launch_velocity.x * time,
					launch_velocity.y * time + 0.5 * bottle_gravity * time * time
				)
				var t = float(i) / steps
				var dot_col = Color(0.2, 0.95, 0.4, 0.8 * (1.0 - t * 0.7))
				draw_circle(local_catch + dot_pos, 3.5 - (t * 1.5), dot_col)
				
	# Draw glass trail
	if is_thrown_back:
		# Glowing cyan trail
		var trail_color = Color(0.1, 0.8, 1.0, 0.25)
		draw_line(Vector2.ZERO, Vector2(-25.0, 0).rotated(rotation), trail_color, 8.0)
		draw_line(Vector2.ZERO, Vector2(-15.0, 0).rotated(rotation), Color(0.3, 0.9, 1.0, 0.6), 5.0)
	elif not is_held:
		# Normal falling trail (faint white/green)
		var trail_color = Color(1.0, 1.0, 1.0, 0.12)
		draw_line(Vector2.ZERO, Vector2(-20.0, 0).rotated(rotation), trail_color, 5.0)

	# Colors for the bottle
	var glass_color = Color(0.2, 0.55, 0.3, 0.65) # Semi-translucent forest green
	var cap_color = Color(0.8, 0.1, 0.1)          # Red cap
	var label_color = Color(0.9, 0.85, 0.7)        # Vintage label
	var line_color = Color(0.1, 0.25, 0.15)        # Dark green outline
	
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
	
	# Cap: from (-4, -22) to (4, -25)
	draw_rect(Rect2(-4, -25, 8, 3), cap_color)
	draw_rect(Rect2(-4, -25, 8, 3), line_color, false, 1.0)
	
	# Shine lines
	draw_line(Vector2(-4, -8), Vector2(-4, 10), Color(1.0, 1.0, 1.0, 0.4), 1.0)
	draw_line(Vector2(-1, -20), Vector2(-1, -12), Color(1.0, 1.0, 1.0, 0.4), 0.8)
