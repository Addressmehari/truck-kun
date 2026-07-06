extends StaticBody2D

var width: float = 240.0
var height: float = 14.0
var belt_speed: float = -200.0 # Speed: negative is backward, positive is forward

var time_elapsed: float = 0.0

func _ready() -> void:
	# Add to group so we can manage or clean up easily
	add_to_group("treadmills")
	
	# Set linear velocity for physical conveyer force
	constant_linear_velocity = Vector2(belt_speed, 0.0)
	
	# Setup the horizontal collision shape
	var col = CollisionShape2D.new()
	var rect = RectangleShape2D.new()
	rect.size = Vector2(width, height)
	col.shape = rect
	
	# Ensure it is drawn on top of the road (z_index 0) but below foreground elements
	z_index = 2
	
	# Position collision to overlap road slightly (top is at -2.0, bottom at height - 2.0)
	col.position = Vector2(0.0, height / 2.0 - 2.0)
	add_child(col)

var _chassis: Node2D = null

func _physics_process(delta: float) -> void:
	# Despawn when left far behind the chassis
	if not is_instance_valid(_chassis):
		_chassis = get_node_or_null("/root/main/truck/chassis")
	if is_instance_valid(_chassis):
		var dist_x = global_position.x - _chassis.global_position.x
		if dist_x < -1200.0:
			queue_free()
			return
		
		# Optimization: Only update and redraw when near the player (within 1200px)
		if abs(dist_x) < 1200.0:
			time_elapsed += delta
			queue_redraw()
	else:
		time_elapsed += delta
		queue_redraw()

func _draw() -> void:
	var half_w = width / 2.0
	
	# Colors matching the industrial theme
	var casing_color = Color(0.14, 0.16, 0.18)
	var casing_border = Color(0.08, 0.08, 0.12)
	var belt_bg = Color(0.18, 0.19, 0.22)
	
	# Use standard bright warning yellow for backward, electric cyan for forward
	var stripe_color = Color(0.92, 0.72, 0.05, 0.8) if belt_speed < 0.0 else Color(0.0, 0.8, 1.0, 0.8)
	
	# Draw main conveyor belt slot
	draw_rect(Rect2(-half_w, -2.0, width, height), belt_bg, true)
	
	# Draw moving caution treads
	var stripe_w := 8.0
	var spacing := 24.0
	var shift = fmod(time_elapsed * belt_speed * 0.9, spacing)
	
	var start_x = -half_w - abs(spacing)
	var end_x = half_w + abs(spacing)
	var curr = start_x + shift
	
	while curr < end_x:
		# Define vertices for slanted belt segments
		var top_l = Vector2(curr - 4.0, -2.0)
		var top_r = Vector2(curr - 4.0 + stripe_w, -2.0)
		var bot_r = Vector2(curr + 4.0 + stripe_w, height - 2.0)
		var bot_l = Vector2(curr + 4.0, height - 2.0)
		
		# Clip to belt boundaries
		top_l.x = clamp(top_l.x, -half_w, half_w)
		top_r.x = clamp(top_r.x, -half_w, half_w)
		bot_r.x = clamp(bot_r.x, -half_w, half_w)
		bot_l.x = clamp(bot_l.x, -half_w, half_w)
		
		if top_l.x < top_r.x and bot_l.x < bot_r.x:
			draw_colored_polygon(PackedVector2Array([top_l, top_r, bot_r, bot_l]), stripe_color)
			
		curr += spacing
		
	# Draw left and right rounded roller casing caps
	draw_circle(Vector2(-half_w, height / 2.0 - 2.0), height / 2.0 + 1.0, casing_color)
	draw_circle(Vector2(half_w, height / 2.0 - 2.0), height / 2.0 + 1.0, casing_color)
	
	# Draw casing borders
	draw_arc(Vector2(-half_w, height / 2.0 - 2.0), height / 2.0 + 1.0, PI/2.0, 3.0*PI/2.0, 16, casing_border, 1.8)
	draw_arc(Vector2(half_w, height / 2.0 - 2.0), height / 2.0 + 1.0, -PI/2.0, PI/2.0, 16, casing_border, 1.8)
	
	# Bottom metallic support plate
	draw_rect(Rect2(-half_w, height - 4.0, width, 4.0), casing_color, true)
	draw_line(Vector2(-half_w, height - 4.0), Vector2(half_w, height - 4.0), casing_border, 1.8)
	
	# Active indicator LEDs blinking at the ends
	var is_lit = sin(time_elapsed * 12.0) > 0.0
	var led_color = (Color(1.0, 0.25, 0.2) if belt_speed < 0.0 else Color(0.0, 0.85, 0.3)) if is_lit else Color(0.3, 0.08, 0.08)
	draw_circle(Vector2(-half_w + 1.0, height / 2.0 - 2.0), 3.0, led_color)
	draw_circle(Vector2(half_w - 1.0, height / 2.0 - 2.0), 3.0, led_color)
