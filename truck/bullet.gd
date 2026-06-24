extends Area2D

var direction := Vector2.RIGHT
var speed := 900.0
var is_enemy := false
var damage := 15.0
var lifetime := 2.2

func _ready() -> void:
	# Add collision detector shape
	var collision = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 6.0
	collision.shape = shape
	add_child(collision)
	
	# Connect collision signals
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
		
	queue_redraw()

func _draw() -> void:
	if is_enemy:
		# Enemy bullet: glowing red/orange plasma
		var core_color = Color(1.0, 0.3, 0.1)
		# Draw fading tail trail
		draw_line(Vector2.ZERO, -direction * 22.0, Color(core_color.r, core_color.g, core_color.b, 0.15), 5.0)
		draw_line(Vector2.ZERO, -direction * 14.0, Color(core_color.r, core_color.g, core_color.b, 0.4), 3.0)
		# Glowing outer aura
		draw_circle(Vector2.ZERO, 6.0, Color(1.0, 0.1, 0.0, 0.3))
		# Main body
		draw_circle(Vector2.ZERO, 4.0, core_color)
		# White hot core
		draw_circle(Vector2.ZERO, 1.8, Color.WHITE)
	else:
		# Player bullet: glowing neon cyan/plasma blue - ultra juicy
		var core_color = Color(0.05, 0.95, 1.0) # Electric cyan
		# Draw fading tail trail
		draw_line(Vector2.ZERO, -direction * 26.0, Color(core_color.r, core_color.g, core_color.b, 0.15), 6.5)
		draw_line(Vector2.ZERO, -direction * 18.0, Color(core_color.r, core_color.g, core_color.b, 0.45), 4.5)
		draw_line(Vector2.ZERO, -direction * 8.0, Color.WHITE, 2.0)
		# Glowing outer aura
		draw_circle(Vector2.ZERO, 7.5, Color(0.0, 0.6, 1.0, 0.35))
		# Main body
		draw_circle(Vector2.ZERO, 5.0, core_color)
		# White hot core
		draw_circle(Vector2.ZERO, 2.2, Color.WHITE)

func _on_area_entered(area: Area2D) -> void:
	# Handle hitting enemies
	if not is_enemy and area.is_in_group("enemies"):
		if area.has_method("take_damage"):
			area.call("take_damage", damage)
			spawn_hit_spark()
			queue_free()

func _on_body_entered(body: Node2D) -> void:
	if is_enemy:
		# If enemy bullet hits the player truck
		if body.name in ["chassis", "container_body"]:
			var truck = body.get_parent()
			if truck and truck.has_method("take_damage"):
				truck.call("take_damage", damage)
				spawn_hit_spark()
				queue_free()
	else:
		# Player bullet hitting obstacles like crates or ground (optional, just destroy bullet)
		if body.name != "chassis" and body.name != "container_body" and not body.name.begins_with("tyre"):
			spawn_hit_spark()
			queue_free()

func spawn_hit_spark() -> void:
	var particles = CPUParticles2D.new()
	particles.amount = 8
	particles.lifetime = 0.25
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.direction = -direction
	particles.spread = 45.0
	particles.gravity = Vector2(0, 50)
	particles.initial_velocity_min = 50.0
	particles.initial_velocity_max = 120.0
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	
	var color = Color(1.0, 0.3, 0.1) if is_enemy else Color(0.1, 0.9, 1.0)
	var ramp = Gradient.new()
	ramp.set_color(0, Color.WHITE)
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	particles.color_ramp = ramp
	
	get_parent().add_child(particles)
	particles.global_position = global_position
	particles.emitting = true
	
	# Free particle node when done
	await get_tree().create_timer(0.35).timeout
	particles.queue_free()
