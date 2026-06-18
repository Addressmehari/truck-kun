extends Control

var truck: Node2D
var chassis: RigidBody2D

# Juice parameters for scaling and shake
var last_velocity := Vector2.ZERO
var shake_offset := Vector2.ZERO
var shake_intensity := 0.0

func _ready() -> void:
	# Wait for parent hierarchy to resolve
	await get_tree().process_frame
	
	truck = get_parent().get_parent() # HUD is child of truck, Dashboard is child of HUD
	if truck:
		chassis = truck.get_node_or_null("chassis")
		
	# Center the pivot offset so the scale pulse scales outward from the center
	pivot_offset = size / 2.0

func _process(delta: float) -> void:
	# 1. Calculate speed
	var speed_kmh = 0.0
	var current_velocity = Vector2.ZERO
	if is_instance_valid(chassis):
		current_velocity = chassis.linear_velocity
		speed_kmh = current_velocity.length() * 0.08
	
	# 2. Scale Gauge Based on Speed (pumps up larger as you accelerate)
	var max_speed_val = 120.0
	var speed_ratio = clamp(speed_kmh / max_speed_val, 0.0, 1.0)
	
	# Breathing idle sway when stationary or very slow
	var breath = sin(Time.get_ticks_msec() * 0.005) * 0.015
	
	# Compute dynamic target scale (goes from 1.0 at idle to 1.18x at top speed)
	var target_scale_val = 1.0 + (speed_ratio * 0.18)
	if speed_ratio < 0.05:
		target_scale_val += breath
		
	# Smoothly interpolate scaling
	scale = scale.lerp(Vector2(target_scale_val, target_scale_val), 10.0 * delta)
	
	# 3. Dynamic Impact Shake (collision detection)
	if delta > 0.0:
		var accel = (current_velocity - last_velocity).length()
		# If the acceleration change is massive (collision/sudden deceleration), trigger shake
		if accel > 400.0:
			shake_intensity = clamp(accel * 0.025, 8.0, 30.0)
	last_velocity = current_velocity
	
	# Decay shake offset
	if shake_intensity > 0.1:
		shake_offset = Vector2(
			randf_range(-shake_intensity, shake_intensity),
			randf_range(-shake_intensity, shake_intensity)
		)
		shake_intensity = lerp(shake_intensity, 0.0, 10.0 * delta)
	else:
		shake_offset = Vector2.ZERO
		
	# Keep pivot centered in case size changes
	pivot_offset = size / 2.0
	
	# Force redrawing
	queue_redraw()

func _draw() -> void:
	# Apply dynamic shake displacement (does not impact canvas anchor coordinates)
	draw_set_transform(shake_offset)
	
	# Center of the 220x220 container
	var speed_center = size / 2.0
	
	# 1. Draw Circular Chrome Bezel (creates a premium 3D circular metallic border)
	# Outer silver ring
	draw_circle(speed_center, 108.0, Color(0.65, 0.68, 0.72)) 
	# Shaded inner rim (bevel)
	draw_circle(speed_center, 104.0, Color(0.45, 0.47, 0.50)) 
	# Bright chrome highlight reflection on the top-left
	draw_circle(speed_center + Vector2(-1.5, -1.5), 102.5, Color(0.85, 0.88, 0.92))
	# Inner dark accent line before the face
	draw_circle(speed_center, 99.0, Color(0.15, 0.16, 0.18))
	
	# 2. Draw Gauge Black Dial Face
	var speed_radius = 96.0
	draw_dial_background(speed_center, speed_radius, "km/h")
	
	# Speedometer marks & numbers
	var max_speed_val = 120.0
	for i in range(0, 13):
		var val = i * 10
		var angle = lerp(-deg_to_rad(210), deg_to_rad(30), float(val) / max_speed_val)
		var dir = Vector2(cos(angle), sin(angle))
		
		# Draw tick mark (longer on tens)
		var tick_len = 12.0 if i % 2 == 0 else 6.0
		var tick_width = 2.5 if i % 2 == 0 else 1.2
		# Colored ticks for higher speeds (orange/red warning zone at 70+ and 90+ km/h)
		var tick_color = Color(0.95, 0.95, 0.98)
		if val >= 90:
			tick_color = Color(1.0, 0.2, 0.1) # red warning zone
		elif val >= 70:
			tick_color = Color(1.0, 0.65, 0.1) # orange warning
			
		draw_line(speed_center + dir * (speed_radius - tick_len), speed_center + dir * speed_radius, tick_color, tick_width)
		
		# Draw numbers on even ticks
		if i % 2 == 0:
			var font = get_theme_default_font()
			# Offset text back along the direction vector to place inside the dial
			var text_pos = speed_center + dir * (speed_radius - 28.0) + Vector2(-16, 6)
			var text_color = Color(0.85, 0.85, 0.9)
			if val >= 90:
				text_color = Color(1.0, 0.5, 0.4) # faded red
			elif val >= 70:
				text_color = Color(1.0, 0.75, 0.5) # faded orange
			draw_string(font, text_pos, str(val), HORIZONTAL_ALIGNMENT_CENTER, 32, 14, text_color)

	# Get speed from chassis for needle rotation
	var speed_kmh = 0.0
	if is_instance_valid(chassis):
		speed_kmh = chassis.linear_velocity.length() * 0.08
	speed_kmh = clamp(speed_kmh, 0.0, max_speed_val)
	
	# Speedometer Needle (Glowing red/orange with shadow)
	var speed_angle = lerp(-deg_to_rad(210), deg_to_rad(30), speed_kmh / max_speed_val)
	var needle_dir = Vector2(cos(speed_angle), sin(speed_angle))
	draw_needle(speed_center, speed_radius - 8.0, needle_dir, Color(1.0, 0.25, 0.1))

func draw_dial_background(center: Vector2, radius: float, label: String) -> void:
	# Deep dark grey/black dial face
	draw_circle(center, radius, Color(0.06, 0.06, 0.08))
	
	# Inner shadow rim for 3D depth
	draw_circle(center, radius - 2.0, Color(0.04, 0.04, 0.05))
	
	# Dynamic subtle blue circular accent ring
	draw_arc(center, radius - 18.0, -deg_to_rad(210), deg_to_rad(30), 64, Color(0.15, 0.45, 0.75, 0.35), 1.5)
	
	# Label inside the dial
	var font = get_theme_default_font()
	draw_string(font, center + Vector2(-30, 42), label, HORIZONTAL_ALIGNMENT_CENTER, 60, 13, Color(0.5, 0.53, 0.58))

func draw_needle(center: Vector2, length: float, dir: Vector2, needle_color: Color) -> void:
	# Needle shadow (shifted down-right)
	draw_line(center + Vector2(3, 3), center + Vector2(3, 3) + dir * length, Color(0, 0, 0, 0.45), 3.5)
	
	# Glowing red needle body
	draw_line(center, center + dir * length, needle_color, 3.0)
	# Bright highlight line inside the needle
	draw_line(center + dir * 4.0, center + dir * (length - 2.0), Color(1.0, 0.8, 0.65), 1.0)
	
	# Metallic Center Cap
	# Outer dark cap ring
	draw_circle(center, 12.0, Color(0.08, 0.08, 0.1))
	# Inner silver ring
	draw_circle(center, 9.0, Color(0.68, 0.70, 0.73))
	# Glossy center dot
	draw_circle(center, 4.0, needle_color)
