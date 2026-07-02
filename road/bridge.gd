extends Node2D

var deck_line: Line2D
var handrail_line: Line2D
var static_body: StaticBody2D
var col_poly: CollisionPolygon2D

var start_pos: Vector2 = Vector2.ZERO
var end_pos: Vector2 = Vector2.ZERO
var plank_length: float = 50.0

var N: int = 15
var points_x: Array[float] = []
var base_y: Array[float] = []
var deflection: Array[float] = []
var vel: Array[float] = []

# Stiffness and Damping parameters configured for an overdamped response (no springy bouncing)
var stiffness: float = 240.0
var damping: float = 34.0

func setup_nodes() -> void:
	if deck_line != null:
		return # Already set up
		
	static_body = StaticBody2D.new()
	static_body.collision_layer = 1
	static_body.collision_mask = 0
	add_child(static_body)
	
	col_poly = CollisionPolygon2D.new()
	static_body.add_child(col_poly)
	
	# Continuous deck rope walkway
	deck_line = Line2D.new()
	deck_line.width = 4.0
	deck_line.default_color = Color(0.24, 0.15, 0.08) # Rope color
	deck_line.z_index = 1
	deck_line.joint_mode = Line2D.LineJointMode.LINE_JOINT_ROUND
	deck_line.begin_cap_mode = Line2D.LineCapMode.LINE_CAP_ROUND
	deck_line.end_cap_mode = Line2D.LineCapMode.LINE_CAP_ROUND
	add_child(deck_line)
	
	# Continuous handrail rope
	handrail_line = Line2D.new()
	handrail_line.width = 3.0
	handrail_line.default_color = Color(0.24, 0.15, 0.08) # Rope color
	handrail_line.z_index = 2
	handrail_line.joint_mode = Line2D.LineJointMode.LINE_JOINT_ROUND
	handrail_line.begin_cap_mode = Line2D.LineCapMode.LINE_CAP_ROUND
	handrail_line.end_cap_mode = Line2D.LineCapMode.LINE_CAP_ROUND
	add_child(handrail_line)

func _ready() -> void:
	setup_nodes()

func initialize_bridge() -> void:
	setup_nodes()
	var span_width = end_pos.x - start_pos.x
	points_x.clear()
	base_y.clear()
	deflection.clear()
	vel.clear()
	
	for k in range(N):
		var t = float(k) / float(N - 1)
		var x_k = start_pos.x + t * span_width
		var y_k = lerp(start_pos.y, end_pos.y, t)
		var baseline_sag = sin(t * PI) * 15.0
		
		points_x.append(x_k)
		base_y.append(y_k)
		deflection.append(baseline_sag)
		vel.append(0.0)
		
	_update_geometry()

func _physics_process(delta: float) -> void:
	if points_x.is_empty():
		return
		
	# Find all active vehicles in the scene tree
	var active_vehicles = []
	var main = get_node_or_null("/root/main")
	if main:
		# Check player truck parts
		var truck = main.get_node_or_null("truck")
		if truck:
			var player_node = truck.get("boat") if truck.get("is_water_mode_active") else truck.get("chassis")
			if not player_node:
				player_node = truck.get_node_or_null("chassis")
			if player_node and is_instance_valid(player_node):
				active_vehicles.append(player_node)
		
		# Check any other rigid body cars / opponents / duck / convoy parts
		for child in main.get_children():
			if child != truck and (child.name.begins_with("Opponent") or child.name.begins_with("TowedCar") or child.name.contains("vehicle") or child.name.contains("car")):
				if is_instance_valid(child) and (child.has_method("get_linear_velocity") or child.get("linear_velocity") != null):
					active_vehicles.append(child)
					
	# Calculate global sag and localized sag contributions for each vehicle
	var max_global_sag = 28.0
	var max_local_sag = 12.0
	
	# For each point, compute dynamic target deflection
	for k in range(N):
		if k == 0 or k == N - 1:
			deflection[k] = 0.0
			vel[k] = 0.0
			continue
			
		var x_k = points_x[k]
		var t = float(k) / float(N - 1)
		
		# Base baseline sag
		var target = sin(t * PI) * 15.0
		
		for veh in active_vehicles:
			var vx = veh.global_position.x
			# If vehicle is within the bridge span
			if vx >= start_pos.x - 20.0 and vx <= end_pos.x + 20.0:
				var vt = clamp((vx - start_pos.x) / (end_pos.x - start_pos.x), 0.0, 1.0)
				
				# 1. Global sag: Entire bridge sags in a smooth sine wave proportional to vehicle distance
				var global_factor = sin(vt * PI)
				target += max_global_sag * global_factor * sin(t * PI)
				
				# 2. Localized sag: Small extra dip directly under the vehicle wheels
				var dist_x = abs(x_k - vx)
				if dist_x < 150.0:
					var local_weight = 1.0 - dist_x / 150.0
					var smooth_weight = (cos((1.0 - local_weight) * PI) + 1.0) / 2.0
					target += max_local_sag * smooth_weight
					
		# Spring-Damper simulation
		var force = -stiffness * (deflection[k] - target) - damping * vel[k]
		vel[k] += force * delta
		deflection[k] += vel[k] * delta
		
	_update_geometry()

func _update_geometry() -> void:
	# Ensure nodes exist
	setup_nodes()
	
	# 1. Update visual deck line (walkway rope)
	var local_pts = PackedVector2Array()
	var top_points = PackedVector2Array()
	
	for k in range(N):
		var rot = get_rotation_at(k)
		var g_pt = Vector2(points_x[k], base_y[k] + deflection[k])
		top_points.append(g_pt)
		local_pts.append(to_local(g_pt))
		
	deck_line.points = local_pts
	
	# 2. Update visual handrail line
	var local_hr_pts = PackedVector2Array()
	local_hr_pts.append(to_local(start_pos + Vector2(0, -22)))
	for k in range(1, N - 1):
		var rot = get_rotation_at(k)
		var up_dir = Vector2.UP.rotated(rot)
		local_hr_pts.append(to_local(top_points[k] + up_dir * 22.0))
	local_hr_pts.append(to_local(end_pos + Vector2(0, -22)))
	handrail_line.points = local_hr_pts
	
	# 3. Update the single CollisionPolygon2D (adds a thick 12px flat collision deck)
	var col_poly_points = PackedVector2Array()
	# Walk left-to-right along the top surface
	for k in range(N):
		col_poly_points.append(to_local(top_points[k]))
		
	# Walk right-to-left along the bottom boundary (12px thickness)
	for k in range(N - 1, -1, -1):
		var rot = get_rotation_at(k)
		var up_dir = Vector2.UP.rotated(rot)
		col_poly_points.append(to_local(top_points[k] + up_dir * -12.0))
		
	col_poly.polygon = col_poly_points
	
	queue_redraw()

func get_rotation_at(k: int) -> float:
	var p_prev = start_pos if k == 0 else Vector2(points_x[k-1], base_y[k-1] + deflection[k-1])
	var p_next = end_pos if k == N-1 else Vector2(points_x[k+1], base_y[k+1] + deflection[k+1])
	return (p_next - p_prev).angle()

func _draw() -> void:
	if points_x.is_empty():
		return
		
	var rope_color = Color(0.24, 0.15, 0.08)
	var wood_color = Color(0.48, 0.31, 0.18)
	var wood_outline = Color(0.28, 0.18, 0.1)
	
	for k in range(N):
		var g_pt = Vector2(points_x[k], base_y[k] + deflection[k])
		var pos = to_local(g_pt)
		var rot = get_rotation_at(k)
		var up_dir = Vector2.UP.rotated(rot)
		
		# Draw vertical rope suspender lines connecting handrail to deck surface
		if k > 0 and k < N - 1:
			draw_line(pos, pos + up_dir * 22.0, rope_color, 1.5)
			
		# Draw wooden slat along the length of each segment
		var right_dir = Vector2.RIGHT.rotated(rot)
		var half_len = (plank_length - 2.0) / 2.0
		var slat_start = pos - right_dir * half_len
		var slat_end = pos + right_dir * half_len
		
		# Wood slat outline
		draw_line(slat_start, slat_end, wood_outline, 14.0)
		# Wood slat body
		draw_line(slat_start, slat_end, wood_color, 10.0)
