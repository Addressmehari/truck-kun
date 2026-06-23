extends Control

signal event_selected(event_name: String)

var target_index := 0
var current_rotation := 0.0
var target_rotation := 0.0
var spin_duration := 4.2 # Real seconds

var is_spinning := false
var is_highlighted := false
var selected_index := -1
var flash_timer := 0.0

# Needle wiggle physics
var needle_tilt := 0.0
var last_sector_index := -1

# References
var panel_center := Vector2.ZERO
var wheel_radius := 200.0

# Labels
var result_label: Label

# Event information
var events = [
	{"name": "Convoy", "icon": "🚚", "color": Color(0.15, 0.42, 0.85), "desc": "CONVOY ARRIVING"},
	{"name": "Storm", "icon": "⛈️", "color": Color(0.1, 0.55, 0.5), "desc": "STORM BREWING"},
	{"name": "Mines", "icon": "💣", "color": Color(0.85, 0.22, 0.18), "desc": "MINES DETECTED"}
]

func _ready() -> void:
	# Capture mouse inputs to block gameplay clicks
	mouse_filter = MOUSE_FILTER_STOP
	
	# Pause gameplay feeling with slow motion
	Engine.time_scale = 0.2
	
	# Set anchors for full screen block
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	grow_horizontal = GROW_DIRECTION_BOTH
	grow_vertical = GROW_DIRECTION_BOTH
	
	# Set initial size and center pivot for pop-in scaling
	var screen_size = get_viewport_rect().size
	size = screen_size
	pivot_offset = screen_size / 2.0
	scale = Vector2.ZERO
	
	# Set panel center
	panel_center = screen_size / 2.0
	
	# Build the Text Labels
	setup_ui_labels()
	
	# Animate pop-in effect
	# Under time_scale = 0.2, we scale up the speed of UI animations to run in normal time!
	var ui_speed_scale = 1.0 / Engine.time_scale # 5.0x speed
	
	var tween_in = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween_in.set_speed_scale(ui_speed_scale)
	tween_in.tween_property(self, "scale", Vector2.ONE, 0.4)
	tween_in.tween_callback(start_spin)

func setup_ui_labels() -> void:
	# Result Label (GTA 5 Style: Placed near the bottom pointer arrow)
	result_label = Label.new()
	result_label.text = "SPINNING..."
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 24)
	result_label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	result_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	result_label.add_theme_constant_override("outline_size", 8)
	add_child(result_label)
	
	# Position Result Label near the bottom pointer arrow (under the wheel)
	result_label.size = Vector2(500, 50)
	result_label.position = panel_center + Vector2(-250, 240)

func start_spin() -> void:
	# 1. Randomly select target event section
	target_index = randi() % 3
	
	# Calculate target rotation
	var mid_angle = (target_index + 0.5) * (2.0 * PI / 3.0)
	# Add natural random offset within the sector (keep away from edges)
	var offset = randf_range(-0.4, 0.4)
	var target_local = mid_angle + offset
	
	# Calculate final rotation to land at the bottom pointer (PI/2)
	# Spin 4 to 6 times
	var spins = 4 + randi() % 3
	target_rotation = PI/2.0 - target_local - spins * 2.0 * PI
	
	is_spinning = true
	is_highlighted = false
	current_rotation = 0.0
	last_sector_index = get_selected_section_index(current_rotation)
	
	# Spin tween
	var ui_speed_scale = 1.0 / Engine.time_scale
	var tween_spin = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUINT)
	tween_spin.set_speed_scale(ui_speed_scale)
	tween_spin.tween_property(self, "current_rotation", target_rotation, spin_duration)
	tween_spin.tween_callback(on_spin_completed)

func _process(delta: float) -> void:
	# Keep center updated in case viewport changes size
	var screen_size = get_viewport_rect().size
	size = screen_size
	panel_center = screen_size / 2.0
	
	if result_label:
		result_label.position = panel_center + Vector2(-250, 240)
		
	# Needle wiggle physics decay
	# Multiply by speed scale so wiggles animate at real-time speed in slow motion
	var ui_speed_scale = 1.0 / Engine.time_scale
	needle_tilt = lerp(needle_tilt, 0.0, 12.0 * delta * ui_speed_scale)
	
	# Check sector boundary crossing for ticking wiggles
	if is_spinning:
		var current_idx = get_selected_section_index(current_rotation)
		if current_idx != last_sector_index:
			# Play tick wiggle
			var diff = current_rotation - target_rotation
			var speed_factor = clamp(diff / (2.0 * PI * 3.0), 0.15, 1.0)
			needle_tilt = 0.45 * speed_factor
			last_sector_index = current_idx
			
		# Live update text/icon near the arrow during spin
		var ev = events[current_idx]
		result_label.text = ev["icon"] + " " + ev["desc"] + " " + ev["icon"]
			
	if is_highlighted:
		flash_timer += delta * ui_speed_scale
		
	queue_redraw()

func on_spin_completed() -> void:
	is_spinning = false
	is_highlighted = true
	selected_index = target_index
	flash_timer = 0.0
	
	# Announce event near the arrow
	var ev = events[selected_index]
	result_label.text = ev["icon"] + " " + ev["desc"] + " " + ev["icon"]
	result_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1)) # Glowing gold
	
	# Pulsing label scale tween
	var ui_speed_scale = 1.0 / Engine.time_scale
	result_label.pivot_offset = result_label.size / 2.0
	var tween_pulse = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tween_pulse.set_speed_scale(ui_speed_scale)
	result_label.scale = Vector2(0.5, 0.5)
	tween_pulse.tween_property(result_label, "scale", Vector2(1.1, 1.1), 0.5)
	
	# Emit selected event signal
	event_selected.emit(ev["name"])
	
	# Wait 1.8 real seconds before closing
	var timer = get_tree().create_timer(1.8 * Engine.time_scale) # Wait in scaled time (1.8 * 0.2 = 0.36s in-game = 1.8s real)
	await timer.timeout
	
	# Animate out
	var tween_out = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween_out.set_speed_scale(ui_speed_scale)
	tween_out.tween_property(self, "scale", Vector2.ZERO, 0.35)
	tween_out.tween_callback(close_popup)

func close_popup() -> void:
	# Restore normal game speed
	Engine.time_scale = 1.0
	queue_free()

# Helper math to see which sector lands at the bottom pointer (PI/2)
func get_selected_section_index(rot: float) -> int:
	var local_angle = PI/2.0 - rot
	local_angle = fposmod(local_angle, 2.0 * PI)
	var sector_angle = 2.0 * PI / 3.0
	var idx = int(local_angle / sector_angle)
	return clamp(idx, 0, 2)

func _draw() -> void:
	# 1. Full Screen Overlay Dim
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.04, 0.65), true)
	
	# 2. Draw Spin Wheel (GTA V Weapon Wheel style)
	var wheel_center = panel_center
	var inner_r = 110.0
	var outer_r = wheel_radius # 200.0
	
	# Determine active sector index
	var active_idx := -1
	if is_spinning:
		active_idx = get_selected_section_index(current_rotation)
	elif is_highlighted:
		active_idx = selected_index
		
	# Draw Segment Slices (Ring Sectors)
	var sector_arc = 2.0 * PI / 3.0
	var gap = 0.04 # Thin gap between sectors in radians for GTA V style
	
	for i in range(3):
		var angle_from = current_rotation + i * sector_arc + gap
		var angle_to = current_rotation + (i + 1) * sector_arc - gap
		
		# Set colors: Active lights up with the event color, inactive is dark charcoal
		var color: Color
		var border_color: Color
		if i == active_idx:
			color = events[i]["color"]
			if is_highlighted:
				# Pulsing effect on the final selected sector
				var flash = abs(sin(flash_timer * 10.0)) * 0.35
				color = color.lightened(flash)
				color.a = 0.95
			else:
				color.a = 0.85
			border_color = Color(1.0, 1.0, 1.0, 0.9) # Bright white border for active
		else:
			color = Color(0.12, 0.14, 0.18, 0.65) # Sleek dark charcoal inactive
			border_color = Color(0.25, 0.28, 0.32, 0.3) # Dim borders
			
		# Draw filled ring sector
		draw_filled_ring_sector(wheel_center, inner_r, outer_r, angle_from, angle_to, color)
		
		# Draw crisp borders around the ring segment
		draw_ring_sector_borders(wheel_center, inner_r, outer_r, angle_from, angle_to, border_color)
		
		# Draw sector text and icons inside the ring
		var mid_angle = angle_from + (angle_to - angle_from) / 2.0
		# Fade out text slightly if not active
		var text_alpha = 1.0 if (i == active_idx) else 0.45
		draw_sector_text(wheel_center, (inner_r + outer_r) / 2.0, mid_angle, events[i]["icon"], events[i]["name"], text_alpha)
		
	# Draw concentric HUD rings to enclose the wheel
	draw_arc(wheel_center, inner_r, 0, 2.0 * PI, 64, Color(1, 1, 1, 0.15), 1.5)
	draw_arc(wheel_center, outer_r, 0, 2.0 * PI, 64, Color(1, 1, 1, 0.15), 1.5)
	
	# Draw active HUD accents in the center
	var accent_color = Color(0.2, 0.55, 0.95, 0.3)
	if is_highlighted:
		accent_color = events[selected_index]["color"]
		accent_color.a = 0.4
	draw_arc(wheel_center, inner_r - 8.0, 0, 2.0 * PI, 64, accent_color, 1.0)
	
	# 3. Draw Bottom Pointer/Needle pointing UP
	var pointer_pivot = wheel_center + Vector2(0, outer_r + 12.0)
	draw_set_transform(pointer_pivot, needle_tilt)
	
	var needle_pts = PackedVector2Array([
		Vector2(-16, 24),
		Vector2(16, 24),
		Vector2(0, -24),
		Vector2(-16, 24)
	])
	draw_polygon(needle_pts, PackedColorArray([Color(1.0, 0.85, 0.15)]))
	draw_polyline(needle_pts, Color(0, 0, 0, 0.85), 2.0)
	draw_circle(Vector2.ZERO, 5.0, Color(0.1, 0.1, 0.12))
	
	# Reset transform
	draw_set_transform(Vector2.ZERO, 0.0)

func draw_filled_ring_sector(center: Vector2, inner_r: float, outer_r: float, angle_from: float, angle_to: float, color: Color) -> void:
	var points = PackedVector2Array()
	var steps := 32
	# Outer arc
	for i in range(steps + 1):
		var a = angle_from + (angle_to - angle_from) * i / steps
		points.append(center + Vector2(cos(a), sin(a)) * outer_r)
	# Inner arc (reversed)
	for i in range(steps, -1, -1):
		var a = angle_from + (angle_to - angle_from) * i / steps
		points.append(center + Vector2(cos(a), sin(a)) * inner_r)
		
	draw_polygon(points, PackedColorArray([color]))

func draw_ring_sector_borders(center: Vector2, inner_r: float, outer_r: float, angle_from: float, angle_to: float, color: Color) -> void:
	var steps := 16
	var outer_pts = PackedVector2Array()
	var inner_pts = PackedVector2Array()
	
	for i in range(steps + 1):
		var a = angle_from + (angle_to - angle_from) * i / steps
		outer_pts.append(center + Vector2(cos(a), sin(a)) * outer_r)
		inner_pts.append(center + Vector2(cos(a), sin(a)) * inner_r)
		
	# Draw outer arc outline
	draw_polyline(outer_pts, color, 1.5)
	# Draw inner arc outline
	draw_polyline(inner_pts, color, 1.5)
	# Draw straight side edges
	draw_line(inner_pts[0], outer_pts[0], color, 1.5)
	draw_line(inner_pts[steps], outer_pts[steps], color, 1.5)

func draw_sector_text(center: Vector2, radius: float, mid_angle: float, icon: String, label: String, alpha: float) -> void:
	var label_pos = center + Vector2(cos(mid_angle), sin(mid_angle)) * radius
	
	# Align text angle radially outwards
	var text_angle = mid_angle
	# If text is on the left half, rotate by 180 degrees to keep it right-side-up
	var normalized_angle = fposmod(mid_angle, 2.0 * PI)
	if normalized_angle > PI / 2.0 and normalized_angle < 3.0 * PI / 2.0:
		text_angle += PI
		
	draw_set_transform(label_pos, text_angle)
	
	var font = get_theme_default_font()
	var full_text = icon + " " + label.to_upper()
	var font_size = 24
	var text_size = font.get_string_size(full_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	
	# Draw shadow
	draw_string(font, Vector2(-text_size.x / 2.0 + 1.5, text_size.y / 4.0 + 1.5), full_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0, 0, 0, 0.7 * alpha))
	# Draw text
	draw_string(font, Vector2(-text_size.x / 2.0, text_size.y / 4.0), full_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(1, 1, 1, alpha))
	
	draw_set_transform(Vector2.ZERO, 0.0)

func draw_panel_corners(rect: Rect2, color: Color) -> void:
	var len := 25.0
	var thick := 3.0
	
	# Top-Left Corner
	draw_line(rect.position, rect.position + Vector2(len, 0), color, thick)
	draw_line(rect.position, rect.position + Vector2(0, len), color, thick)
	
	# Top-Right Corner
	var tr = rect.position + Vector2(rect.size.x, 0)
	draw_line(tr, tr + Vector2(-len, 0), color, thick)
	draw_line(tr, tr + Vector2(0, len), color, thick)
	
	# Bottom-Left Corner
	var bl = rect.position + Vector2(0, rect.size.y)
	draw_line(bl, bl + Vector2(len, 0), color, thick)
	draw_line(bl, bl + Vector2(0, -len), color, thick)
	
	# Bottom-Right Corner
	var br = rect.position + rect.size
	draw_line(br, br + Vector2(-len, 0), color, thick)
	draw_line(br, br + Vector2(0, -len), color, thick)
