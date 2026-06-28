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

# References
var chassis: RigidBody2D

# Touch/Swipe tracking
var pressed_on_bottle := false
var press_start_pos := Vector2.ZERO
var is_drag_active := false
var last_mouse_pos := Vector2.ZERO

func _ready() -> void:
	# Enable input pickable to get events, though we also do a global backup check
	input_pickable = true
	
	# Add collision shape
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 20.0
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

func _physics_process(delta: float) -> void:
	if is_exploding:
		return
		
	# Rotate the bottle as it flies
	rotation += rotation_speed * delta
	
	# Compute truck's current velocity
	var truck_vel_x = 550.0
	if is_instance_valid(chassis):
		truck_vel_x = chassis.linear_velocity.x
		
	# Apply gravity
	velocity.y += bottle_gravity * delta
	
	# Update position
	# Horizontal velocity tracks the chassis + our relative horizontal speed
	global_position.x += (truck_vel_x + relative_vel_x) * delta
	global_position.y += velocity.y * delta
	
	# Offscreen / missed cleanup
	if global_position.y > 900.0 or global_position.x < (chassis.global_position.x - 800.0 if is_instance_valid(chassis) else 0.0):
		queue_free()
		
	queue_redraw()

func _input(event: InputEvent) -> void:
	if is_exploding or is_thrown_back:
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_pos = get_global_mouse_position()
			if event.pressed:
				is_drag_active = true
				last_mouse_pos = mouse_pos
				# Check if clicked directly on/near the bottle
				if global_position.distance_to(mouse_pos) < 40.0:
					pressed_on_bottle = true
					press_start_pos = mouse_pos
			else:
				is_drag_active = false
				if pressed_on_bottle:
					# Released without dragging much: it's a TAP!
					if mouse_pos.distance_to(press_start_pos) < 15.0:
						break_bottle()
					pressed_on_bottle = false
					
	elif event is InputEventMouseMotion:
		if is_drag_active:
			var curr_mouse_pos = get_global_mouse_position()
			if pressed_on_bottle:
				# Clicked on bottle and dragged away: SWIPE!
				if curr_mouse_pos.distance_to(press_start_pos) >= 15.0:
					var swipe_dir = (curr_mouse_pos - press_start_pos).normalized()
					throw_back(swipe_dir)
					pressed_on_bottle = false
			else:
				# Started dragging outside and swiped through the bottle
				var d = get_distance_to_segment(global_position, last_mouse_pos, curr_mouse_pos)
				if d < 40.0:
					var swipe_dir = (curr_mouse_pos - last_mouse_pos).normalized()
					throw_back(swipe_dir)
			last_mouse_pos = curr_mouse_pos

func get_distance_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab = b - a
	var ap = p - a
	var ab_len_sq = ab.length_squared()
	if ab_len_sq == 0.0:
		return p.distance_to(a)
	var t = clamp(ap.dot(ab) / ab_len_sq, 0.0, 1.0)
	var projection = a + t * ab
	return p.distance_to(projection)

func throw_back(swipe_dir: Vector2) -> void:
	if is_thrown_back:
		return
	is_thrown_back = true
	
	# Biased throw towards left (where enemies are chasing)
	var throw_dir = swipe_dir
	if throw_dir.x > -0.2:
		throw_dir.x = -0.8
		throw_dir = throw_dir.normalized()
		
	var throw_speed = 750.0
	relative_vel_x = throw_dir.x * throw_speed
	velocity.y = throw_dir.y * throw_speed * 0.6
	
	# Double the spin speed for nice arcade effect
	rotation_speed = randf_range(12.0, 18.0) * (-1.0 if rotation_speed < 0 else 1.0)
	
	spawn_deflect_sparks()

func break_bottle() -> void:
	if is_exploding:
		return
	is_exploding = true
	
	# Shatter particles
	var particles = CPUParticles2D.new()
	particles.amount = 22
	particles.lifetime = 0.55
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.direction = Vector2.ZERO
	particles.spread = 180.0
	particles.gravity = Vector2(0, 220)
	particles.initial_velocity_min = 90.0
	particles.initial_velocity_max = 180.0
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 5.0
	
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
	
	await get_tree().create_timer(0.6).timeout
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
	if is_exploding:
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
	if is_exploding:
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

func _draw() -> void:
	if is_exploding:
		return
		
	# Draw glass trail
	if is_thrown_back:
		# Glowing cyan trail
		var trail_color = Color(0.1, 0.8, 1.0, 0.25)
		draw_line(Vector2.ZERO, Vector2(-25.0, 0).rotated(rotation), trail_color, 8.0)
		draw_line(Vector2.ZERO, Vector2(-15.0, 0).rotated(rotation), Color(0.3, 0.9, 1.0, 0.6), 5.0)
	else:
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
