@tool
extends Area2D

var parent_system: Node2D

var is_active: bool = false:
	set(val):
		if is_active != val:
			is_active = val
			queue_redraw()
			if is_active:
				play_press_effect()
			else:
				play_release_effect()

var plate_length: float = 120.0:
	set(val):
		plate_length = val
		queue_redraw()
		# Update collision shape rect size if it exists
		var shape_node = get_node_or_null("CollisionShape2D")
		if shape_node:
			var rect = shape_node.shape as RectangleShape2D
			if rect:
				rect.size.x = plate_length

func _ready() -> void:
	parent_system = get_parent()
	body_entered.connect(_on_body_changed)
	body_exited.connect(_on_body_changed)
	
	# Setup Steam/Dust Particles
	var particles = get_node_or_null("SteamParticles")
	if not particles:
		particles = CPUParticles2D.new()
		particles.name = "SteamParticles"
		particles.amount = 15
		particles.lifetime = 0.5
		particles.one_shot = true
		particles.explosiveness = 0.95
		particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		particles.emission_rect_extents = Vector2(plate_length / 2.0, 2.0)
		particles.direction = Vector2(0, -1)
		particles.spread = 35.0
		particles.gravity = Vector2(0, -120) # Steam rises
		particles.initial_velocity_min = 30.0
		particles.initial_velocity_max = 60.0
		particles.scale_amount_min = 3.0
		particles.scale_amount_max = 6.0
		
		var ramp = Gradient.new()
		ramp.set_color(0, Color(0.9, 0.9, 0.9, 0.5))
		ramp.set_color(1, Color(0.9, 0.9, 0.9, 0.0))
		particles.color_ramp = ramp
		
		add_child(particles)

func _on_body_changed(_body) -> void:
	var pressed = false
	for b in get_overlapping_bodies():
		if b is RigidBody2D:
			pressed = true
			break
	is_active = pressed
	if parent_system and parent_system.has_method("_on_plate_state_changed"):
		parent_system.call("_on_plate_state_changed", is_active)

func play_press_effect() -> void:
	var particles = get_node_or_null("SteamParticles")
	if particles:
		particles.restart()
		particles.emitting = true

func play_release_effect() -> void:
	pass

func _draw() -> void:
	# Casing / Base Frame
	var base_height = 8.0
	var base_rect = Rect2(-plate_length / 2.0, -base_height, plate_length, base_height)
	draw_rect(base_rect, Color(0.18, 0.18, 0.2), true) # Dark metal casing
	
	# Draw warning yellow and black stripes
	var stripe_width = 12.0
	var num_stripes = int(plate_length / stripe_width)
	var stripe_color = Color(0.85, 0.65, 0.1) # Warning Yellow
	
	for i in range(num_stripes + 2):
		var x_pos = -plate_length/2.0 + (i * stripe_width) - base_height
		var p1 = Vector2(x_pos, -base_height)
		var p2 = Vector2(x_pos + base_height, 0.0)
		
		# Clamp lines within casing X bounds
		p1.x = clamp(p1.x, -plate_length/2.0, plate_length/2.0)
		p2.x = clamp(p2.x, -plate_length/2.0, plate_length/2.0)
		
		draw_line(p1, p2, stripe_color, 4.0)
		
	# Draw the moving plate piece on top
	# Moves down by 4 pixels when active
	var plate_offset_y = -3.0 if is_active else -7.0
	var plate_thick = 4.0
	var plate_rect = Rect2(-plate_length / 2.0 + 4.0, plate_offset_y, plate_length - 8.0, plate_thick)
	
	# Red indicator lines on plate top surface when unpressed, green when pressed
	var plate_color = Color(0.3, 0.65, 0.4) if is_active else Color(0.45, 0.45, 0.48)
	draw_rect(plate_rect, plate_color, true)
	
	# Status LEDs on the base sides (glow green if active, red if inactive)
	var led_color = Color(0.2, 0.9, 0.3) if is_active else Color(0.9, 0.2, 0.2)
	# Left LED
	draw_circle(Vector2(-plate_length/2.0 + 8.0, -base_height/2.0), 2.5, led_color)
	draw_circle(Vector2(-plate_length/2.0 + 8.0, -base_height/2.0), 1.0, Color(1, 1, 1, 0.8)) # Light core
	# Right LED
	draw_circle(Vector2(plate_length/2.0 - 8.0, -base_height/2.0), 2.5, led_color)
	draw_circle(Vector2(plate_length/2.0 - 8.0, -base_height/2.0), 1.0, Color(1, 1, 1, 0.8)) # Light core
