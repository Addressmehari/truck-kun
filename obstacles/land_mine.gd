extends Area2D

var is_active := true
var pulse_time := 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	
	# Setup a CollisionShape2D if it doesn't exist
	var collision = get_node_or_null("CollisionShape2D")
	if not collision:
		collision = CollisionShape2D.new()
		var shape = RectangleShape2D.new()
		shape.size = Vector2(40.0, 16.0)
		collision.shape = shape
		# Placed resting on top of the road surface
		collision.position = Vector2(0.0, -8.0)
		add_child(collision)
		
	# Setup Explosion Particles (smoke & fire)
	var particles = CPUParticles2D.new()
	particles.name = "ExplosionParticles"
	particles.amount = 40
	particles.lifetime = 0.8
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.direction = Vector2(0, -1)
	particles.spread = 60.0
	particles.gravity = Vector2(0, 100)
	particles.initial_velocity_min = 120.0
	particles.initial_velocity_max = 240.0
	particles.scale_amount_min = 6.0
	particles.scale_amount_max = 14.0
	
	var ramp = Gradient.new()
	ramp.set_color(0, Color(1.0, 0.9, 0.1, 1.0)) # Bright yellow core
	ramp.set_color(1, Color(0.2, 0.2, 0.25, 0.0)) # Faded dark smoke
	ramp.add_point(0.25, Color(1.0, 0.35, 0.0, 1.0)) # Fire orange
	ramp.add_point(0.55, Color(0.4, 0.4, 0.45, 0.65)) # Gray smoke
	particles.color_ramp = ramp
	
	add_child(particles)

func _process(delta: float) -> void:
	if not is_active:
		return
		
	# Find distance to truck chassis to dynamically speed up flash rate
	var flash_speed = 4.0
	var truck = get_node_or_null("../truck")
	if truck:
		var chassis = truck.get_node_or_null("chassis")
		if chassis:
			var dist = global_position.distance_to(chassis.global_position)
			if dist < 600.0:
				flash_speed = lerp(20.0, 4.0, clamp(dist / 600.0, 0.0, 1.0))
				
	pulse_time += delta * flash_speed
	queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if not is_active:
		return
		
	# Check if the colliding body is the chassis, container, or tyres
	var is_truck = false
	if body.name in ["chassis", "container_body"] or body.name.begins_with("tyre"):
		is_truck = true
		
	if is_truck:
		explode()

func explode() -> void:
	is_active = false
	visible = true # Ensure particles show
	
	# Blast physics: apply massive upward force to truck chassis and container
	var parent = get_parent()
	if parent:
		var truck = parent.get_node_or_null("truck")
		if truck:
			var chassis = truck.get_node_or_null("chassis") as RigidBody2D
			var container = truck.get_node_or_null("container_body") as RigidBody2D
			
			if chassis:
				chassis.apply_central_impulse(Vector2(0, -6500.0))
				chassis.apply_torque_impulse(randf_range(-8000.0, 8000.0))
			if container:
				container.apply_central_impulse(Vector2(0, -5000.0))
				
			# Trigger dashboard/camera shake
			var dashboard = truck.get_node_or_null("HUD/Dashboard")
			if dashboard and "shake_intensity" in dashboard:
				dashboard.shake_intensity = 35.0 # Max impact shake
				
	# Restart particle boom
	var particles = get_node_or_null("ExplosionParticles") as CPUParticles2D
	if particles:
		particles.restart()
		particles.emitting = true
		
	# Play dynamic sound/effect cue (print or screen-flash)
	print("BOOM! Mine exploded!")
	
	# Hide visual mine geometry but wait for particles to complete before freeing
	queue_redraw()
	await get_tree().create_timer(1.2).timeout
	queue_free()

func _draw() -> void:
	if not is_active:
		return
		
	var size_x = 36.0
	var size_y = 10.0
	
	# Draw Mine Body (dark metal shell)
	var shell_rect = Rect2(-size_x / 2.0, -size_y, size_x, size_y)
	draw_rect(shell_rect, Color(0.24, 0.25, 0.28), true)
	draw_rect(shell_rect, Color(0.12, 0.13, 0.15), false, 2.0)
	
	# Yellow warning line
	draw_line(Vector2(-size_x / 2.0 + 4, -size_y + 3), Vector2(size_x / 2.0 - 4, -size_y + 3), Color(0.85, 0.65, 0.1), 1.5)
	
	# Flashing red LED on top center trigger plate
	var flash_val = sin(pulse_time)
	var led_color = Color(0.95, 0.15, 0.1) if flash_val > 0.0 else Color(0.2, 0.05, 0.05)
	
	# Drawing indicator core
	draw_circle(Vector2(0.0, -size_y - 2), 3.0, led_color)
	if flash_val > 0.0:
		draw_circle(Vector2(0.0, -size_y - 2), 1.5, Color(1, 1, 1, 0.95)) # Core glow
