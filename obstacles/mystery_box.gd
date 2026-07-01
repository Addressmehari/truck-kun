@tool
extends Area2D

# ─── Config ───────────────────────────────────────────────────────────────────
@export var cube_size: float = 26.0
@export var line_width: float = 2.0
@export var glow_intensity: float = 1.0

# ─── State ────────────────────────────────────────────────────────────────────
var _elapsed: float = 0.0
var _collected: bool = false
var _collection_timer: float = 0.0
var _collection_duration: float = 0.8
var _particles: Array[Dictionary] = []

var angle_x: float = 0.0
var angle_y: float = 0.0
var angle_z: float = 0.0

var _road: StaticBody2D = null
var _base_y: float = 0.0
var _hover_offset: float = 0.0

# Custom Font reference for the "?"
const FONT_PATH: String = "res://retro_font.ttf"
var custom_font: Font

# 3D vertices of a unit cube
var vertices: Array[Vector3] = [
	Vector3(-1, -1, -1), # 0: Back-Bottom-Left
	Vector3( 1, -1, -1), # 1: Back-Bottom-Right
	Vector3( 1,  1, -1), # 2: Back-Top-Right
	Vector3(-1,  1, -1), # 3: Back-Top-Left
	Vector3(-1, -1,  1), # 4: Front-Bottom-Left
	Vector3( 1, -1,  1), # 5: Front-Bottom-Right
	Vector3( 1,  1,  1), # 6: Front-Top-Right
	Vector3(-1,  1,  1)  # 7: Front-Top-Left
]

# 6 faces of the cube (each with 4 vertex indices)
var faces: Array[Dictionary] = [
	{ "indices": [0, 1, 2, 3], "color": Color(0.0, 0.9, 1.0, 0.12) }, # Back face (Cyan)
	{ "indices": [4, 5, 6, 7], "color": Color(0.0, 0.9, 1.0, 0.12) }, # Front face (Cyan)
	{ "indices": [0, 1, 5, 4], "color": Color(0.0, 0.9, 1.0, 0.12) }, # Bottom face
	{ "indices": [2, 3, 7, 6], "color": Color(0.0, 0.9, 1.0, 0.12) }, # Top face
	{ "indices": [0, 3, 7, 4], "color": Color(0.0, 0.9, 1.0, 0.12) }, # Left face
	{ "indices": [1, 2, 6, 5], "color": Color(0.0, 0.9, 1.0, 0.12) }  # Right face
]

# 12 wireframe edges
var edges: Array[Array] = [
	[0, 1], [1, 2], [2, 3], [3, 0], # Back face edges
	[4, 5], [5, 6], [6, 7], [7, 4], # Front face edges
	[0, 4], [1, 5], [2, 6], [3, 7]  # Side connecting edges
]

func rotate_x(v: Vector3, angle: float) -> Vector3:
	var c = cos(angle)
	var s = sin(angle)
	return Vector3(v.x, v.y * c - v.z * s, v.y * s + v.z * c)

func rotate_y(v: Vector3, angle: float) -> Vector3:
	var c = cos(angle)
	var s = sin(angle)
	return Vector3(v.x * c - v.z * s, v.y, v.x * s + v.z * c)

func rotate_z(v: Vector3, angle: float) -> Vector3:
	var c = cos(angle)
	var s = sin(angle)
	return Vector3(v.x * c - v.y * s, v.x * s + v.y * c, v.z)

func _ready() -> void:
	if ResourceLoader.exists(FONT_PATH):
		custom_font = load(FONT_PATH)
	else:
		custom_font = ThemeDB.fallback_font
		
	if Engine.is_editor_hint():
		return
		
	add_to_group("mystery_boxes")
	_road = get_node_or_null("/root/main/Road")
	_hover_offset = randf_range(0.0, TAU)
	body_entered.connect(_on_body_entered)
	set_process(true)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_elapsed += delta
		angle_x += 0.8 * delta
		angle_y += 1.2 * delta
		angle_z += 0.5 * delta
		queue_redraw()
		return

	_elapsed += delta
	
	if _collected:
		_collection_timer += delta
		# Update particles with velocity and drag
		for p in _particles:
			p.vel = p.vel * (1.0 - p.drag * delta)
			p.pos += p.vel * delta
			
		if _collection_timer >= _collection_duration:
			queue_free()
			return
		queue_redraw()
		return
		
	# Rotate the cube on all axes
	angle_x += 0.8 * delta
	angle_y += 1.2 * delta
	angle_z += 0.5 * delta
	
	# Hover bobbing movement
	if _road and _road.has_method("get_road_height"):
		_base_y = _road.call("get_road_height", global_position.x)
	var hover = sin(_elapsed * 2.8 + _hover_offset) * 10.0 - 55.0
	position.y = _base_y + hover
	
	queue_redraw()

func _on_body_entered(body: Node2D) -> void:
	if Engine.is_editor_hint():
		return
	if _collected:
		return
	var is_truck_part = (
		body.is_in_group("truck") or
		body.name == "chassis" or
		body.name == "boat" or
		body.name.begins_with("tyre")
	)
	if not is_truck_part:
		return
		
	var col = get_node_or_null("CollisionShape2D")
	if col:
		col.set_deferred("disabled", true)
		
	print("Mystery box collected at x = ", global_position.x)
	trigger_collection_animation()

func trigger_collection_animation() -> void:
	_collected = true
	_collection_timer = 0.0
	
	# Trigger camera/dashboard screen shake
	var dashboard = get_node_or_null("/root/main/truck/HUD/Dashboard")
	if dashboard and "shake_intensity" in dashboard:
		dashboard.shake_intensity = 35.0 # Max impact arcade screen shake!
	
	# Generate 50 high-velocity exploding particles
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	for i in range(50):
		var angle = rng.randf_range(0.0, TAU)
		var speed = rng.randf_range(200.0, 750.0) # High-velocity blast particles!
		var vel = Vector2(cos(angle), sin(angle)) * speed
		var colors = [Color("#00f0ff"), Color("#ff2a6d"), Color("#ffea79"), Color(1.0, 1.0, 1.0)]
		var color = colors[rng.randi_range(0, colors.size() - 1)]
		_particles.append({
			"pos": Vector2.ZERO,
			"vel": vel,
			"color": color,
			"size": rng.randf_range(4.0, 8.0), # Larger, more visible sparks
			"drag": rng.randf_range(1.2, 2.5)
		})
		
	# Defer the event trigger to the next frame to prevent infinite recursion during chunk regeneration
	call_deferred("_trigger_random_event")

func _trigger_random_event() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	# Trigger random event: Crusher (50%) or Convoy (50%)
	var event_roll = rng.randf()
	if event_roll < 0.5:
		print("[MysteryBox] Triggering Crusher Event!")
		var road = get_node_or_null("/root/main/Road")
		if road and road.has_method("spawn_crusher_on_next_chunk"):
			road.call("spawn_crusher_on_next_chunk")
	else:
		print("[MysteryBox] Triggering Convoy Event!")
		var truck = get_node_or_null("/root/main/truck")
		if truck and truck.has_method("start_active_event"):
			# Remove any existing event timer bars safely first
			var existing = truck.get_node_or_null("HUD/EventTimerBar")
			if existing:
				existing.queue_free()
				
			truck.call("start_active_event", "Convoy")
			
			var timer_script = load("res://ui/event_timer_bar.gd")
			if timer_script and truck.has_node("HUD"):
				var timer_bar = Control.new()
				timer_bar.set_script(timer_script)
				var hud = truck.get_node("HUD")
				hud.add_child(timer_bar)
				# Roll target distance using Gaussian distribution: mean=550.0, deviation=30.0, clamp[500, 600]
				var u1 = rng.randf()
				if u1 < 0.0001: u1 = 0.0001
				var u2 = rng.randf()
				var norm = sqrt(-2.0 * log(u1)) * cos(TAU * u2)
				var event_dist = clamp(550.0 + norm * 30.0, 500.0, 600.0)
				timer_bar.call("setup", "Convoy", "🚚", Color(0.15, 0.42, 0.85), event_dist)

func _draw() -> void:
	if Engine.is_editor_hint():
		_draw_cube()
		return
		
	if _collected:
		_draw_explosion()
		return
		
	_draw_cube()

func _draw_cube() -> void:
	# Draw a hovering shadow on the road
	var shadow_y = _base_y - position.y
	if Engine.is_editor_hint():
		shadow_y = 55.0
	var shadow_scale = clamp(1.0 - (shadow_y / 150.0), 0.3, 1.0)
	var shadow_color = Color(0.0, 0.0, 0.0, 0.45 * shadow_scale)
	draw_ellipse(Vector2(0, shadow_y), Vector2(cube_size * 1.5 * shadow_scale, cube_size * 0.4 * shadow_scale), shadow_color)
	
	# 1. Rotate all 3D vertices and project them
	var rot_verts: Array[Vector3] = []
	var proj_verts: Array[Vector2] = []
	for v in vertices:
		var rv = rotate_z(rotate_y(rotate_x(v, angle_x), angle_y), angle_z)
		rot_verts.append(rv)
		
		# Simple 3D projection to 2D
		var p2d = Vector2(rv.x, rv.y) * cube_size
		proj_verts.append(p2d)
		
	# 2. Depth sort the faces (lowest Z average is drawn first/back, highest Z is drawn last/front)
	var face_depths = []
	for i in range(faces.size()):
		var f = faces[i]
		var sum_z = 0.0
		for idx in f.indices:
			sum_z += rot_verts[idx].z
		face_depths.append({ "index": i, "depth": sum_z / 4.0 })
		
	face_depths.sort_custom(func(a, b): return a.depth < b.depth)
	
	# 3. Draw faces (back-to-front)
	for fd in face_depths:
		var f = faces[fd.index]
		var poly = PackedVector2Array()
		for idx in f.indices:
			poly.append(proj_verts[idx])
			
		# Make the color pulse slightly for extra visual flair
		var pulse = (sin(_elapsed * 4.0) + 1.0) * 0.05
		var face_color = f.color
		face_color.a = clamp(face_color.a + pulse, 0.05, 0.30)
		
		# Draw solid transparent face
		draw_colored_polygon(poly, face_color)
		
		# Draw thin neon border around this specific face
		var border_color = Color(0.2, 0.9, 1.0, 0.3)
		draw_polyline(poly, border_color, 1.0)
		
	# 4. Draw wireframe edges on top (crisp and glowing)
	var edge_color = Color(0.1, 0.85, 1.0, 0.9) # Glowing neon cyan
	for edge in edges:
		draw_line(proj_verts[edge[0]], proj_verts[edge[1]], edge_color, line_width)
		
	# 5. Draw glowing nodes/points at each vertex
	var vertex_color = Color(0.4, 0.95, 1.0, 0.95)
	for pt in proj_verts:
		draw_circle(pt, 2.5, vertex_color)
		
	# 6. Draw "?" text in the absolute center
	if custom_font:
		var q_text = "?"
		var font_size = 32
		# Add a subtle neon scale pulse to the text
		var text_pulse = 1.0 + sin(_elapsed * 6.0) * 0.08
		
		# Calculate string size to center it perfectly
		var text_size = custom_font.get_string_size(q_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos = Vector2(-text_size.x * 0.5 * text_pulse, text_size.y * 0.35 * text_pulse)
		
		# Draw glowing background drop shadow for the text
		var glow_color = Color(1.0, 0.0, 0.5, 0.6) # Glowing magenta
		draw_string(custom_font, text_pos + Vector2(1, 1), q_text, HORIZONTAL_ALIGNMENT_CENTER, -1, int(font_size * text_pulse), glow_color)
		draw_string(custom_font, text_pos + Vector2(-1, -1), q_text, HORIZONTAL_ALIGNMENT_CENTER, -1, int(font_size * text_pulse), glow_color)
		
		# Draw foreground text
		var front_color = Color(1.0, 0.85, 0.2, 1.0) # Golden yellow
		draw_string(custom_font, text_pos, q_text, HORIZONTAL_ALIGNMENT_CENTER, -1, int(font_size * text_pulse), front_color)

func _draw_explosion() -> void:
	var progress = _collection_timer / _collection_duration
	var alpha = 1.0 - progress
	
	# 1. Draw a dramatic, rapid core flash
	if progress < 0.35:
		var flash_alpha = (0.35 - progress) / 0.35
		draw_circle(Vector2.ZERO, flash_alpha * 85.0, Color(1.0, 1.0, 1.0, flash_alpha * 0.9))
		draw_circle(Vector2.ZERO, flash_alpha * 45.0, Color(1.0, 0.9, 0.3, flash_alpha * 0.95))
	
	# 2. Draw 3 expanding neon shockwave rings at different speeds
	var ring_cyan_radius = progress * 170.0
	var ring_magenta_radius = progress * 260.0
	var ring_gold_radius = progress * 340.0
	
	draw_arc(Vector2.ZERO, ring_cyan_radius, 0.0, TAU, 48, Color(0.0, 0.9, 1.0, alpha * 0.8), 3.0)
	draw_arc(Vector2.ZERO, ring_magenta_radius, 0.0, TAU, 48, Color(1.0, 0.1, 0.6, alpha * 0.6), 2.0)
	draw_arc(Vector2.ZERO, ring_gold_radius, 0.0, TAU, 48, Color(1.0, 0.85, 0.2, alpha * 0.4), 1.5)
	
	# 3. Draw expanding particles
	for p in _particles:
		var p_alpha = alpha
		var p_size = p.size * alpha
		
		# Draw a glowing center
		var p_color = p.color
		p_color.a = p_alpha
		draw_circle(p.pos, p_size, p_color)
		
		# Draw a dramatic speed line (streak) pointing back to the center
		var trail_length = 0.24 # Longer trails for high speed
		var prev_pos = p.pos - p.vel * trail_length
		var trail_color = p.color
		trail_color.a = p_alpha * 0.5
		draw_line(prev_pos, p.pos, trail_color, 2.0)

# Draw an ellipse helper since Godot 4 doesn't have draw_ellipse by default
func draw_ellipse(center: Vector2, extents: Vector2, color: Color) -> void:
	var points = PackedVector2Array()
	var steps = 24
	for i in range(steps):
		var angle = (float(i) / steps) * TAU
		points.append(center + Vector2(cos(angle) * extents.x, sin(angle) * extents.y))
	draw_colored_polygon(points, color)
