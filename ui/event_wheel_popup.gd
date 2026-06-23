extends Control

signal event_selected(event_name: String)

var target_index := 0
var current_rotation := 0.0
var target_rotation := 0.0
var spin_duration := 2.5 # Real seconds

var is_spinning := false
var is_highlighted := false
var selected_index := -1
var flash_timer := 0.0

# Needle wiggle physics
var needle_tilt := 0.0
var last_sector_index := -1

# References
var panel_center := Vector2.ZERO
var wheel_radius := 120.0

# Labels
var title_label: Label
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
	# Title Label
	title_label = Label.new()
	title_label.text = "RANDOM EVENT ENCOUNTER"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2)) # Glowing Gold
	title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	title_label.add_theme_constant_override("outline_size", 6)
	add_child(title_label)
	
	# Position Title relative to screen center
	title_label.size = Vector2(400, 40)
	title_label.position = panel_center + Vector2(-200, -220)
	
	# Result Label
	result_label = Label.new()
	result_label.text = "SPINNING..."
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 28)
	result_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	result_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	result_label.add_theme_constant_override("outline_size", 8)
	add_child(result_label)
	
	# Position Result Label
	result_label.size = Vector2(400, 50)
	result_label.position = panel_center + Vector2(-200, 170)

func start_spin() -> void:
	# 1. Randomly select target event section
	target_index = randi() % 3
	
	# Calculate target rotation
	var mid_angle = (target_index + 0.5) * (2.0 * PI / 3.0)
	# Add natural random offset within the sector (keep away from edges)
	var offset = randf_range(-0.4, 0.4)
	var target_local = mid_angle + offset
	
	# Calculate final rotation to land at the top pointer (-PI/2)
	# Spin 4 to 6 times
	var spins = 4 + randi() % 3
	target_rotation = -PI/2.0 - target_local - spins * 2.0 * PI
	
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
	
	if title_label:
		title_label.position = panel_center + Vector2(-200, -220)
	if result_label:
		result_label.position = panel_center + Vector2(-200, 170)
		
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
			
	if is_highlighted:
		flash_timer += delta * ui_speed_scale
		
	queue_redraw()

func on_spin_completed() -> void:
	is_spinning = false
	is_highlighted = true
	selected_index = target_index
	flash_timer = 0.0
	
	# Announce event
	var ev = events[selected_index]
	result_label.text = ev["icon"] + " " + ev["desc"] + " " + ev["icon"]
	result_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1)) # Glowing gold
	
	# Pulsing label scale tween
	var ui_speed_scale = 1.0 / Engine.time_scale
	result_label.pivot_offset = result_label.size / 2.0
	var tween_pulse = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	tween_pulse.set_speed_scale(ui_speed_scale)
	result_label.scale = Vector2(0.5, 0.5)
	tween_pulse.tween_property(result_label, "scale", Vector2(1.15, 1.15), 0.5)
	
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

# Helper math to see which sector lands at the top pointer (-PI/2)
func get_selected_section_index(rot: float) -> int:
	var local_angle = -PI/2.0 - rot
	local_angle = fposmod(local_angle, 2.0 * PI)
	var sector_angle = 2.0 * PI / 3.0
	var idx = int(local_angle / sector_angle)
	return clamp(idx, 0, 2)

func _draw() -> void:
	# 1. Full Screen Overlay Dim
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.04, 0.65), true)
	
	# 2. Main Glassmorphic Panel
	var panel_size = Vector2(440, 520)
	var panel_rect = Rect2(panel_center - panel_size / 2.0, panel_size)
	
	# Dark backdrop
	draw_rect(panel_rect, Color(0.08, 0.08, 0.12, 0.88), true)
	
	# Sleek glowing border
	# We'll draw 3 nested outlines for a premium neon glow effect
	var border_color = Color(0.2, 0.55, 0.95) # Cyberpunk Cyan/Blue
	if is_highlighted:
		border_color = events[selected_index]["color"]
		
	draw_rect(panel_rect, border_color * Color(1, 1, 1, 0.15), false, 6.0)
	draw_rect(panel_rect, border_color * Color(1, 1, 1, 0.4), false, 3.0)
	draw_rect(panel_rect, border_color * Color(1, 1, 1, 0.95), false, 1.2)
	
	# Decorative corner highlights
	draw_panel_corners(panel_rect, border_color)
	
	# 3. Draw Spin Wheel
	var wheel_center = panel_center + Vector2(0, -10)
	
	# Bezel Outer Ring
	draw_circle(wheel_center, wheel_radius + 16.0, Color(0.04, 0.04, 0.06))
	draw_circle(wheel_center, wheel_radius + 12.0, Color(0.18, 0.20, 0.24))
	draw_circle(wheel_center, wheel_radius + 9.0, Color(0.06, 0.06, 0.08))
	
	# Draw Sector Slices
	var sector_arc = 2.0 * PI / 3.0
	for i in range(3):
		var angle_from = current_rotation + i * sector_arc
		var angle_to = angle_from + sector_arc
		
		# Colors & highlights
		var color = events[i]["color"]
		
		# If highlighted, fade out non-selected sectors
		if is_highlighted:
			if i != selected_index:
				color.a = 0.22
			else:
				# Flashing pulsing effect on the winning sector
				var flash = abs(sin(flash_timer * 10.0)) * 0.35
				color = color.lightened(flash)
				color.a = 1.0
		else:
			color.a = 0.85
			
		# Draw filled sector slice
		draw_filled_sector(wheel_center, wheel_radius, angle_from, angle_to, color)
		
		# Draw sector separating lines
		draw_line(wheel_center, wheel_center + Vector2(cos(angle_from), sin(angle_from)) * wheel_radius, Color(0,0,0,0.65), 3.0)
		
		# Draw sector text and icons
		var mid_angle = angle_from + sector_arc / 2.0
		draw_sector_text(wheel_center, wheel_radius, mid_angle, events[i]["icon"], events[i]["name"], color.a)
		
	# Draw inner hub cap to complete the wheel look
	draw_circle(wheel_center, 22.0, Color(0.05, 0.05, 0.06))
	draw_circle(wheel_center, 18.0, Color(0.25, 0.28, 0.32))
	draw_circle(wheel_center, 8.0, Color(0.08, 0.08, 0.1))
	
	# Outer glowing ring over the wheel edges
	draw_arc(wheel_center, wheel_radius, 0, 2.0 * PI, 64, Color(1, 1, 1, 0.12), 3.0)
	draw_arc(wheel_center, wheel_radius + 4.0, 0, 2.0 * PI, 64, border_color * Color(1, 1, 1, 0.6), 1.5)
	
	# 4. Draw Top Pointer/Needle (Wiggles on ticks)
	var pointer_pivot = wheel_center + Vector2(0, -wheel_radius - 8.0)
	draw_set_transform(pointer_pivot, needle_tilt)
	
	# Triangular pointer pointing down
	var needle_pts = PackedVector2Array([
		Vector2(-12, -18),
		Vector2(12, -18),
		Vector2(0, 18),
		Vector2(-12, -18)
	])
	draw_polygon(needle_pts, PackedColorArray([Color(1.0, 0.85, 0.15)]))
	draw_polyline(needle_pts, Color(0, 0, 0, 0.85), 2.0)
	# Needle center cap dot
	draw_circle(Vector2.ZERO, 4.0, Color(0.1, 0.1, 0.12))
	
	# Reset transform
	draw_set_transform(Vector2.ZERO, 0.0)

func draw_filled_sector(center: Vector2, radius: float, angle_from: float, angle_to: float, color: Color) -> void:
	var points = PackedVector2Array()
	points.append(center)
	var steps := 32
	for i in range(steps + 1):
		var a = angle_from + (angle_to - angle_from) * i / steps
		points.append(center + Vector2(cos(a), sin(a)) * radius)
		
	draw_polygon(points, PackedColorArray([color]))

func draw_sector_text(center: Vector2, radius: float, mid_angle: float, icon: String, label: String, alpha: float) -> void:
	var label_pos = center + Vector2(cos(mid_angle), sin(mid_angle)) * (radius * 0.58)
	
	# Align text angle radially outwards
	var text_angle = mid_angle
	# If text is on the left half, rotate by 180 degrees to keep it right-side-up
	var normalized_angle = fposmod(mid_angle, 2.0 * PI)
	if normalized_angle > PI / 2.0 and normalized_angle < 3.0 * PI / 2.0:
		text_angle += PI
		
	draw_set_transform(label_pos, text_angle)
	
	var font = get_theme_default_font()
	var full_text = icon + " " + label.to_upper()
	var font_size = 18
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
