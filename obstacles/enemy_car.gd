extends Area2D

# Config
var max_health := 60.0
var health := 60.0
var speed := 550.0
var target_distance := 450.0
var shoot_cooldown := 2.2
var cooldown_timer := 0.0

# References
var road: Node2D
var truck: Node2D
var chassis: Node2D

# VFX/State
var flash_timer := 0.0
var is_exploding := false

func _ready() -> void:
	add_to_group("enemies")
	
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
	tween.tween_property(self, "scale", Vector2.ONE, 0.5)

func _physics_process(delta: float) -> void:
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
		
	queue_redraw()

func snap_to_road() -> void:
	if road and road.has_method("get_road_height"):
		var ry = road.call("get_road_height", position.x)
		position.y = ry
		
		# Find angle/slope
		var ry_front = road.call("get_road_height", position.x + 20.0)
		var ry_back = road.call("get_road_height", position.x - 20.0)
		rotation = (Vector2(40.0, ry_front - ry_back)).angle()

func shoot_at_player() -> void:
	if not is_instance_valid(chassis):
		return
		
	cooldown_timer = shoot_cooldown + randf_range(-0.4, 0.4)
	
	var bullet_script = load("res://truck/bullet.gd")
	if bullet_script:
		# Direction towards chassis center
		var target_pos = chassis.global_position + Vector2(0, -20)
		var turret_pos = global_position + Vector2(0, -32).rotated(rotation)
		var dir = (target_pos - turret_pos).normalized()
		
		var bullet = Area2D.new()
		bullet.set_script(bullet_script)
		bullet.name = "EnemyBullet"
		bullet.is_enemy = true
		bullet.direction = dir
		bullet.damage = 10.0
		
		get_parent().add_child(bullet)
		bullet.global_position = turret_pos

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
		
	# Modulate geometry to red if flashing on hit
	var car_color = Color(0.85, 0.2, 0.2) # Red sports combat car
	if flash_timer > 0.0:
		car_color = Color(1.0, 1.0, 1.0) # White hitflash
		
	var metal_trim = Color(0.12, 0.14, 0.16)
	var window_col = Color(0.1, 0.1, 0.12)
	
	# 1. Wheels (Two wheels at the base of chassis)
	var w1_pos = Vector2(-22, -4)
	var w2_pos = Vector2(22, -4)
	for w_pos in [w1_pos, w2_pos]:
		draw_circle(w_pos, 8.5, metal_trim)
		draw_circle(w_pos, 5.0, Color(0.5, 0.5, 0.55)) # Silver rims
		draw_circle(w_pos, 2.0, Color.BLACK)
		
	# 2. Main Car Body
	# Skewed polygon for streamlined retro sports car body
	var body_pts = PackedVector2Array([
		Vector2(-38, -6),
		Vector2(38, -6),
		Vector2(34, -20),
		Vector2(16, -20),
		Vector2(6, -30),
		Vector2(-24, -30),
		Vector2(-34, -18)
	])
	draw_colored_polygon(body_pts, car_color)
	draw_polyline(body_pts, metal_trim, 2.0)
	
	# Windshield / Cabin Glass
	var wind_pts = PackedVector2Array([
		Vector2(14, -20),
		Vector2(6, -28),
		Vector2(-4, -28),
		Vector2(-2, -20)
	])
	draw_colored_polygon(wind_pts, window_col)
	draw_polyline(wind_pts, metal_trim, 1.2)
	
	# Spoiler Wing (rear wing)
	draw_rect(Rect2(-36, -24, 6, 6), car_color, true)
	draw_line(Vector2(-38, -24), Vector2(-30, -24), metal_trim, 2.5)
	
	# 3. Turret / Gun Barrel on Top (pointing towards the player/forward)
	var turret_pivot = Vector2(-5.0, -32.0)
	draw_circle(turret_pivot, 5.5, metal_trim)
	
	# Barrel pointing forward (pointing right)
	var turret_angle = 0.0
	if is_instance_valid(chassis):
		turret_angle = (chassis.global_position - global_position).angle() - rotation
		
	# Draw rotated barrel line
	var barrel_dir = Vector2.RIGHT.rotated(turret_angle)
	draw_line(turret_pivot, turret_pivot + barrel_dir * 18.0, metal_trim, 3.5)
	draw_circle(turret_pivot + barrel_dir * 18.0, 2.2, Color.RED) # laser designator tip
