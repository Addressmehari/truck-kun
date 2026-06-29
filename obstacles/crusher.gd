extends AnimatableBody2D

# Crusher types
enum CrusherType { CLASSIC, SAWBLADE, CHAINSAW }
@export var crusher_type: CrusherType = CrusherType.CLASSIC

@export var up_wait_time := 1.5
@export var slam_time := 0.25
@export var down_wait_time := 1.0
@export var rise_time := 0.75
@export var travel_distance := 180.0

var time_elapsed := 0.0
var start_y := 0.0
var initialized := false
var rotation_angle := 0.0

var _chassis: Node2D = null

func _ready() -> void:
	# Add to group so we can manage or find crushers easily if needed
	add_to_group("crushers")
	
	# Randomize type: 70% CLASSIC (the box ones), 20% SAWBLADE, 10% CHAINSAW
	var r = randf()
	if r < 0.70:
		crusher_type = CrusherType.CLASSIC
	elif r < 0.90:
		crusher_type = CrusherType.SAWBLADE
	else:
		crusher_type = CrusherType.CHAINSAW
	
	# Hide or show flat rectangular block based on type
	var block = get_node_or_null("Block")
	if block:
		block.visible = (crusher_type == CrusherType.CLASSIC)
		
	# Adjust the shaft length to connect perfectly with the visual center of the head
	var shaft = get_node_or_null("Shaft")
	if shaft:
		if crusher_type == CrusherType.CLASSIC:
			shaft.offset_bottom = -40.0
		else:
			shaft.offset_bottom = -20.0
		
	# Update the collision shape to match the selected crusher type
	var col_shape = get_node_or_null("CollisionShape2D")
	if col_shape:
		if crusher_type == CrusherType.CLASSIC:
			# Keep original RectangleShape2D layout
			var rect = RectangleShape2D.new()
			rect.size = Vector2(100.0, 80.0)
			col_shape.shape = rect
			col_shape.position = Vector2.ZERO
		elif crusher_type == CrusherType.SAWBLADE:
			# Circular sawblade collision shape
			var circle = CircleShape2D.new()
			circle.radius = 45.0
			col_shape.shape = circle
			col_shape.position = Vector2.ZERO
		elif crusher_type == CrusherType.CHAINSAW:
			# Capsule-like rectangle collision shape for chainsaw bar
			var rect = RectangleShape2D.new()
			rect.size = Vector2(100.0, 65.0)
			col_shape.shape = rect
			col_shape.position = Vector2.ZERO

func initialize_crusher_position(spawn_x: float, road_y: float) -> void:
	# Keep bottom alignments touching the road when fully slammed
	global_position = Vector2(spawn_x, road_y - 40.0)
	start_y = global_position.y
	initialized = true

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	if not initialized:
		start_y = global_position.y
		initialized = true
		
	# Despawn when left far behind the chassis
	if not is_instance_valid(_chassis):
		_chassis = get_node_or_null("/root/main/truck/chassis")
	if is_instance_valid(_chassis):
		if global_position.x < _chassis.global_position.x - 1200.0:
			queue_free()
			return
		
	# Spin the sawblade angle
	rotation_angle += delta * 15.0
	
	time_elapsed += delta
	var cycle_duration = up_wait_time + slam_time + down_wait_time + rise_time
	var local_time = fmod(time_elapsed, cycle_duration)
	
	var y_offset := 0.0
	
	if local_time < up_wait_time:
		y_offset = travel_distance
	elif local_time < up_wait_time + slam_time:
		var t = (local_time - up_wait_time) / slam_time
		y_offset = lerp(travel_distance, 0.0, t * t)
	elif local_time < up_wait_time + slam_time + down_wait_time:
		y_offset = 0.0
	else:
		var t = (local_time - (up_wait_time + slam_time + down_wait_time)) / rise_time
		y_offset = lerp(0.0, travel_distance, t * (2.0 - t))
		
	global_position.y = start_y - y_offset
	
	if crusher_type != CrusherType.CLASSIC:
		queue_redraw()

func _draw() -> void:
	if crusher_type == CrusherType.CLASSIC:
		return
		
	var center := Vector2.ZERO
	
	if crusher_type == CrusherType.SAWBLADE:
		# Draw the spinning sawblade / shuriken
		var blade_color = Color(0.78, 0.8, 0.83) # Steel
		var highlight_color = Color(0.95, 0.96, 0.98) # Sharp edges
		var shadow_color = Color(0.38, 0.4, 0.43) # Shadowed backs
		var core_color = Color(0.12, 0.13, 0.16) # Dark core
		var hazard_glow = Color(1.0, 0.38, 0.0) # Glowing orange-red center
		
		var teeth_count := 6
		var outer_radius := 45.0
		var inner_radius := 24.0
		var center_radius := 11.0
		
		for i in range(teeth_count):
			var angle_start = rotation_angle + i * (TAU / teeth_count)
			var angle_tip = angle_start + 0.42
			var angle_dip = rotation_angle + (i + 1) * (TAU / teeth_count) - 0.08
			
			var p_start = center + Vector2(cos(angle_start), sin(angle_start)) * inner_radius
			var p_tip = center + Vector2(cos(angle_tip), sin(angle_tip)) * outer_radius
			var p_dip = center + Vector2(cos(angle_dip), sin(angle_dip)) * inner_radius
			
			draw_colored_polygon(PackedVector2Array([p_start, p_tip, p_dip]), blade_color)
			draw_polyline(PackedVector2Array([p_start, p_tip]), highlight_color, 2.0)
			draw_polyline(PackedVector2Array([p_tip, p_dip]), shadow_color, 1.2)
			
		draw_circle(center, inner_radius, blade_color)
		draw_arc(center, inner_radius, 0.0, TAU, 32, shadow_color, 1.8)
		
		draw_circle(center, center_radius, core_color)
		draw_arc(center, center_radius, 0.0, TAU, 16, Color(0.08, 0.08, 0.12), 2.0)
		
		var pulse = abs(sin(time_elapsed * 8.0)) * 2.0
		draw_circle(center, 4.0 + pulse, Color(hazard_glow.r, hazard_glow.g, hazard_glow.b, 0.35))
		draw_circle(center, 3.2, hazard_glow)
		draw_circle(center, 1.2, Color.WHITE)
		
	elif crusher_type == CrusherType.CHAINSAW:
		# Draw the vertical guide bar and moving chainsaw chain
		var bar_color = Color(0.22, 0.24, 0.28) # Metallic grey
		var highlight_color = Color(0.92, 0.72, 0.05) # Yellow stripes
		var chain_color = Color(0.75, 0.77, 0.8) # Shiny teeth
		var groove_color = Color(0.1, 0.11, 0.13) # Inside track
		
		var A := 46.0 # Horizontal radius
		var B := 24.0 # Vertical radius
		
		# 1. Guide bar main body
		var bar_points = PackedVector2Array()
		for idx in range(32):
			var phi = idx * (TAU / 32.0)
			bar_points.append(center + Vector2(cos(phi) * A, sin(phi) * B))
		draw_colored_polygon(bar_points, bar_color)
		draw_polyline(bar_points, Color(0.08, 0.08, 0.12), 2.5)
		
		# 2. Dark inner chain groove/track
		var groove_points = PackedVector2Array()
		for idx in range(32):
			var phi = idx * (TAU / 32.0)
			groove_points.append(center + Vector2(cos(phi) * (A - 6.0), sin(phi) * (B - 4.0)))
		draw_colored_polygon(groove_points, groove_color)
		
		# 3. Center yellow caution graphic on the guide bar
		draw_line(center - Vector2(25, 0), center + Vector2(25, 0), highlight_color, 4.0)
		draw_circle(center, 5.0, Color.WHITE)
		draw_circle(center, 2.0, Color.BLACK)
		
		# 4. Moving chainsaw teeth
		var N := 12
		var track_offset = time_elapsed * 12.0 # Fast chain movement speed
		for k in range(N):
			var theta = track_offset + k * (TAU / float(N))
			var p_cos = cos(theta)
			var p_sin = sin(theta)
			var pos = center + Vector2(p_cos * A, p_sin * B)
			
			var tangent = Vector2(-p_sin * A, p_cos * B).normalized()
			var normal = Vector2(p_cos, p_sin).normalized()
			
			# Construct tooth points
			var tip = pos + tangent * 5.0 + normal * 8.0
			var back = pos - tangent * 7.0 + normal * 1.5
			var base = pos - tangent * 2.0
			
			draw_colored_polygon(PackedVector2Array([base, tip, back]), chain_color)
			draw_polyline(PackedVector2Array([back, tip]), Color.WHITE, 1.5) # Sharp cutting edge
			draw_polyline(PackedVector2Array([base, back]), Color(0.35, 0.37, 0.4), 1.0)
