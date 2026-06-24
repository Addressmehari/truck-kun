extends Node2D

var gun_rotation := 0.0
var shoot_cooldown := 0.22
var cooldown_timer := 0.0
var pop_percent := 0.0 # Used for pop-in animation
var crosshair_pop := 0.0 # Juiced scale pop when shooting

func _ready() -> void:
	# Hide system mouse cursor
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	
	# Tween to pop up from inside the container
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "pop_percent", 1.0, 0.6)
	
	# Create a dedicated top-layer crosshair node so it renders on top of everything
	var crosshair = CrosshairHelper.new()
	crosshair.name = "Crosshair"
	crosshair.gunner = self
	crosshair.z_index = 100
	crosshair.z_as_relative = false
	add_child(crosshair)

func _exit_tree() -> void:
	# Restore system mouse cursor when Gunner is removed
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	if cooldown_timer > 0.0:
		cooldown_timer -= delta
		
	# Decelerate crosshair pop scale
	crosshair_pop = lerp(crosshair_pop, 0.0, 16.0 * delta)
		
	# Point gun at mouse cursor
	var mouse_pos = get_global_mouse_position()
	var to_mouse = mouse_pos - global_position
	gun_rotation = to_mouse.angle()
	
	# Request redraw on top-level crosshair
	var crosshair = get_node_or_null("Crosshair")
	if crosshair:
		crosshair.queue_redraw()
		
	queue_redraw()

func _input(event: InputEvent) -> void:
	if cooldown_timer <= 0.0:
		if (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed) or (event is InputEventScreenTouch and event.pressed):
			shoot()

func shoot() -> void:
	cooldown_timer = shoot_cooldown
	crosshair_pop = 1.0 # Trigger juice crosshair pop!
	
	# Spawn bullet
	var bullet_script = load("res://truck/bullet.gd")
	if bullet_script:
		var bullet = Area2D.new()
		bullet.set_script(bullet_script)
		bullet.name = "PlayerBullet"
		bullet.is_enemy = false
		bullet.direction = Vector2.RIGHT.rotated(gun_rotation)
		
		# Bullet spawn point: offset in the direction of the gun barrel
		var barrel_length = 32.0
		var spawn_pos = global_position + Vector2.RIGHT.rotated(gun_rotation) * barrel_length
		
		# Add to current scene so it moves in global space
		get_tree().current_scene.add_child(bullet)
		bullet.global_position = spawn_pos
		
		# Visual kickback shake on the gunner
		position.x -= 4.0
		var tween = create_tween().set_ease(Tween.EASE_OUT)
		tween.tween_property(self, "position:x", -95.0, 0.15) # Lerp back to default local X

func _draw() -> void:
	# Apply pop-up vertical offset (-45 pixels max height)
	var visual_offset = Vector2(0.0, (1.0 - pop_percent) * 45.0)
	draw_set_transform(visual_offset, 0.0, Vector2.ONE)
	
	# Colors
	var helmet_col := Color(0.24, 0.38, 0.22)   # Army green helmet
	var skin_col := Color(0.98, 0.85, 0.7)       # Skin tone
	var suit_col := Color(0.12, 0.35, 0.6)       # Blue combat outfit
	var gun_col := Color(0.15, 0.16, 0.18)       # Metallic dark grey
	var scope_col := Color(0.2, 0.2, 0.22)
	var clip_col := Color(0.1, 0.1, 0.12)
	
	var is_silhouette := false
	var road = get_node_or_null("/root/main/Road")
	if road and road.has_method("get_current_biome"):
		var biome = road.call("get_current_biome")
		if biome and biome.get("use_silhouette_truck") == true:
			is_silhouette = true
			
	if is_silhouette:
		helmet_col = Color.BLACK
		skin_col = Color.BLACK
		suit_col = Color.BLACK
		gun_col = Color.BLACK
		scope_col = Color.BLACK
		clip_col = Color.BLACK
	
	# 1. Draw Body Torso (emerging from container)
	# Draw skewed rectangle for torso
	var torso_points = PackedVector2Array([
		Vector2(-14, 20),
		Vector2(14, 20),
		Vector2(10, -8),
		Vector2(-10, -8)
	])
	draw_colored_polygon(torso_points, suit_col)
	draw_polyline(torso_points, Color.BLACK, 1.5)
	
	# 2. Draw Head (Skin colored circle)
	draw_circle(Vector2(0, -18), 10.0, skin_col)
	draw_circle(Vector2(0, -18), 10.0, Color.BLACK, false, 1.5)
	
	# Face detail: aiming eye block
	draw_rect(Rect2(2, -22, 6, 4), Color.BLACK, true)
	
	# 3. Draw Helmet
	var helmet_points = PackedVector2Array()
	var steps = 12
	for i in range(steps + 1):
		var a = PI + (PI * i / steps)
		helmet_points.append(Vector2(cos(a), sin(a)) * 11.5 + Vector2(0, -20))
	draw_colored_polygon(helmet_points, helmet_col)
	draw_polyline(helmet_points, Color.BLACK, 1.5)
	
	# Helmet rim line
	draw_line(Vector2(-12, -20), Vector2(12, -20), Color.BLACK, 2.0)
	
	# 4. Draw Gun Arm (pivot and barrel pointing towards target)
	# Apply local rotation to match gun pivot aiming
	draw_set_transform(visual_offset + Vector2(0, -2), gun_rotation - rotation, Vector2.ONE)
	
	# Gun base / hand
	draw_circle(Vector2.ZERO, 5.0, skin_col)
	draw_circle(Vector2.ZERO, 5.0, Color.BLACK, false, 1.2)
	
	# Gun Receiver (main body of gun)
	draw_rect(Rect2(-8, -4, 18, 8), gun_col, true)
	draw_rect(Rect2(-8, -4, 18, 8), Color.BLACK, false, 1.5)
	
	# Barrel
	draw_rect(Rect2(10, -2.5, 14, 5), gun_col, true)
	draw_rect(Rect2(10, -2.5, 14, 5), Color.BLACK, false, 1.5)
	
	# Scope
	draw_rect(Rect2(-2, -6.5, 10, 3.5), scope_col, true)
	draw_rect(Rect2(-2, -6.5, 10, 3.5), Color.BLACK, false, 1.0)
	
	# Clip/Magazine
	draw_rect(Rect2(2, 4, 4, 7), clip_col, true)
	draw_rect(Rect2(2, 4, 4, 7), Color.BLACK, false, 1.0)

# Handles rendering the crosshair reticle on the dedicated absolute top layer
func _draw_crosshair(helper: Node2D) -> void:
	var local_mouse = helper.to_local(get_global_mouse_position())
	
	# Scale animation based on shoot pop
	var pop_scale = 1.0 + crosshair_pop * 0.5
	var r_outer = 11.0 * pop_scale
	var r_inner = 5.0 * pop_scale
	var c_color = Color(1.0, 0.22, 0.18) # Neon red
	var outline_color = Color(0.0, 0.0, 0.0, 0.7)
	
	# Draw center dot
	helper.draw_circle(local_mouse, 1.5 * pop_scale, c_color)
	helper.draw_circle(local_mouse, 1.5 * pop_scale, outline_color, false, 1.0)
	
	# Draw outer circle (dashed look: 4 arcs or simple circle)
	helper.draw_circle(local_mouse, r_outer, Color(c_color.r, c_color.g, c_color.b, 0.4), false, 1.5)
	helper.draw_circle(local_mouse, r_outer, outline_color, false, 2.5)
	helper.draw_circle(local_mouse, r_outer, c_color, false, 1.0)
	
	# Draw crosshair ticks (North, South, West, East)
	# Top tick
	helper.draw_line(local_mouse + Vector2(0, -r_inner), local_mouse + Vector2(0, -r_outer - 3.0), outline_color, 2.5)
	helper.draw_line(local_mouse + Vector2(0, -r_inner), local_mouse + Vector2(0, -r_outer - 3.0), c_color, 1.2)
	# Bottom tick
	helper.draw_line(local_mouse + Vector2(0, r_inner), local_mouse + Vector2(0, r_outer + 3.0), outline_color, 2.5)
	helper.draw_line(local_mouse + Vector2(0, r_inner), local_mouse + Vector2(0, r_outer + 3.0), c_color, 1.2)
	# Left tick
	helper.draw_line(local_mouse + Vector2(-r_inner, 0), local_mouse + Vector2(-r_outer - 3.0, 0), outline_color, 2.5)
	helper.draw_line(local_mouse + Vector2(-r_inner, 0), local_mouse + Vector2(-r_outer - 3.0, 0), c_color, 1.2)
	# Right tick
	helper.draw_line(local_mouse + Vector2(r_inner, 0), helper.to_local(get_global_mouse_position()) + Vector2(r_outer + 3.0, 0), outline_color, 2.5)
	helper.draw_line(local_mouse + Vector2(r_inner, 0), helper.to_local(get_global_mouse_position()) + Vector2(r_outer + 3.0, 0), c_color, 1.2)

# Dedicated rendering child class to bypass parent Z ordering constraints
class CrosshairHelper extends Node2D:
	var gunner: Node2D
	func _draw() -> void:
		if is_instance_valid(gunner):
			gunner._draw_crosshair(self)
