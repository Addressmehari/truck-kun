extends Control

var event_name: String = ""
var event_icon: String = ""
var duration: float = 15.0
var time_left: float = 15.0
var event_color: Color = Color(0.2, 0.6, 1.0, 0.9)
var is_active := false
var elapsed_time := 0.0

func setup(ev_name: String, ev_icon: String, ev_color: Color, ev_duration: float = 15.0) -> void:
	event_name = ev_name
	event_icon = ev_icon
	event_color = ev_color
	duration = ev_duration
	time_left = ev_duration
	is_active = true
	
	# Set layout anchors to top center
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	
	grow_horizontal = GROW_DIRECTION_BOTH
	grow_vertical = GROW_DIRECTION_END
	
	# Enlarged height bounds (580px wide, 130px tall) to fit the taller cells
	offset_left = -290
	offset_right = 290
	offset_top = -140 # Start offscreen
	offset_bottom = -10
	
	# Set name for easy lookup
	name = "EventTimerBar"
	
	# Slide down animation using offsets
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "offset_top", 20.0, 0.5)
	tween.tween_property(self, "offset_bottom", 150.0, 0.5)
	
	# Regenerate road chunks immediately so existing tunnels disappear instantly at start of event
	var road = get_node_or_null("/root/main/Road")
	if road and road.has_method("regenerate_runtime_chunks"):
		road.call("regenerate_runtime_chunks")

func _process(delta: float) -> void:
	if not is_active:
		return
		
	elapsed_time += delta
	
	# Smoothly decrease time_left
	time_left -= delta
	if time_left <= 0.0:
		time_left = 0.0
		is_active = false
		end_event()
		
	queue_redraw()

func end_event() -> void:
	print("Event ended: ", event_name)
	
	# 1. Restore Sky Background Modulate to default (Color.WHITE)
	var sky = get_node_or_null("/root/main/ParallaxBackground/ParallaxLayer")
	if sky:
		var sprite = sky.get_node_or_null("Sprite2D")
		if sprite:
			var tween = create_tween()
			tween.tween_property(sprite, "modulate", Color.WHITE, 1.5)
			
	# 2. Find and clean up any dynamic rain/storm particles
	var main_node = get_node_or_null("/root/main")
	if main_node:
		var particles = main_node.find_child("StormRainParticles", true, false)
		if particles:
			# Fade out particles before freeing
			var tween_part = create_tween()
			tween_part.tween_property(particles, "modulate:a", 0.0, 1.0)
			tween_part.tween_callback(particles.queue_free)
			
	# 3. Call callback hooks if main script, road, or truck needs to perform custom cleanups
	if main_node and main_node.has_method("end_active_event"):
		main_node.call("end_active_event", event_name)
		
	var road = get_node_or_null("/root/main/Road")
	if road and road.has_method("end_active_event"):
		road.call("end_active_event", event_name)
	# Regenerate road chunks immediately so tunnels can spawn again after event ends
	if road and road.has_method("regenerate_runtime_chunks"):
		road.call("regenerate_runtime_chunks")
		
	var truck = get_node_or_null("/root/main/truck")
	if truck and truck.has_method("end_active_event"):
		truck.call("end_active_event", event_name)

	# Slide up offscreen using offsets and queue free
	var tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "offset_top", -140.0, 0.4)
	tween.tween_property(self, "offset_bottom", -10.0, 0.4)
	tween.tween_callback(queue_free)

func _draw() -> void:
	# NO backing panel/outline box drawn here - clean floating HUD elements only
	
	# Draw text: Event icon + event name
	var font = get_theme_default_font()
	var font_size = 28
	
	var text_label = event_name.to_upper()
	if event_icon != "":
		text_label = event_icon + "  " + text_label
		
	var text_size = font.get_string_size(text_label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	
	# Bob the text slightly for extra retro arcade juice
	var text_bob = cos(elapsed_time * 4.0) * 2.0
	var text_pos = Vector2((size.x - text_size.x) / 2.0, 38 + text_bob)
	
	# Large text shadow
	draw_string(font, text_pos + Vector2(2, 2), text_label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0, 0, 0, 0.85))
	# Main text color (clean off-white)
	draw_string(font, text_pos, text_label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0.95, 0.96, 0.98))
	
	# Draw 10 Segmented Retro Arcade Cells (Taller slanted cells with dark outline and bobbing animation)
	var cell_w := 44.0
	var cell_h := 55.0 # Taller retro audio level meter height style
	var cell_gap := 8.0
	var start_x := (size.x - (10.0 * cell_w + 9.0 * cell_gap)) / 2.0
	var bar_y := 60.0
	
	# Convert remaining time to a discrete integer cell count (0 to 10)
	var active_cells_count = int(ceil((time_left / duration) * 10.0))
	
	# Slant factor (italic tilt for speed/style)
	var slant := -6.0
	# Pure bold dark outline color for cartoon arcade look
	var outline_color := Color(0.08, 0.08, 0.12)
	var outline_width := 3.0
	
	for i in range(10):
		# 1. Spring spawn scale animation (EASE_OUT_BACK overshoot)
		var t = elapsed_time - 0.4 - (i * 0.05)
		var cell_scale = 0.0
		if t > 0.0:
			var dur = 0.35
			if t < dur:
				var x = (t / dur) - 1.0
				cell_scale = x * x * (2.70158 * x + 1.70158) + 1.0
			else:
				cell_scale = 1.0
				
		if cell_scale <= 0.01:
			continue
			
		# Funky bobbing wave animation (equalizer style)
		var bob = sin(elapsed_time * 6.0 + i * 0.75) * 4.0
			
		# Center coordinates of this specific cell for scaling
		var cell_center_x = start_x + i * (cell_w + cell_gap) + cell_w / 2.0
		var cell_center_y = bar_y + cell_h / 2.0
		
		# Compute scaled width and height for pop-in scaling bounce
		var curr_w = cell_w * cell_scale
		var curr_h = cell_h * cell_scale
		var cell_rect = Rect2(cell_center_x - curr_w / 2.0, cell_center_y - curr_h / 2.0, curr_w, curr_h)
		
		# Compute retro warning colors: Green (0-2), Yellow (3-6), Red (7-9)
		var cell_color = Color(0.2, 0.85, 0.3) # Green default
		if i >= 7:
			cell_color = Color(1.0, 0.25, 0.2) # Red danger zone
		elif i >= 3:
			cell_color = Color(0.98, 0.85, 0.1) # Yellow warning zone
		
		# 2. Draw cell background container (dark frame slot)
		var bg_c = Color(0.18, 0.2, 0.25, 0.55)
		draw_slanted_cell(cell_rect, bg_c, outline_color, outline_width, slant, bob)
		
		# 3. Draw active cell highlights (no smooth partial fills)
		if i < active_cells_count - 1:
			# Fully charged highlighted cell (bright zone color with bold dark outline)
			draw_slanted_cell(cell_rect, cell_color, outline_color, outline_width, slant, bob)
		elif i == active_cells_count - 1:
			# The active cell currently ticking down (pulses/blinks in full width)
			var pulse = abs(sin(elapsed_time * 12.0)) * 0.55 + 0.45
			var pulse_color = cell_color
			pulse_color.a = pulse
			
			draw_slanted_cell(cell_rect, pulse_color, outline_color, outline_width, slant, bob)

# Helper function to draw a slanted (italic) vector cell with a bold dark outline
func draw_slanted_cell(rect: Rect2, color: Color, outline_color: Color, outline_width: float, slant: float, bob: float) -> void:
	var tl = Vector2(rect.position.x + slant, rect.position.y + bob)
	var tr = Vector2(rect.position.x + rect.size.x + slant, rect.position.y + bob)
	var br = Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y + bob)
	var bl = Vector2(rect.position.x, rect.position.y + rect.size.y + bob)
	
	# Filled skewed polygon
	var points = PackedVector2Array([tl, tr, br, bl])
	draw_colored_polygon(points, color)
	
	# Thick, closed outer border line
	var outline_points = PackedVector2Array([tl, tr, br, bl, tl])
	draw_polyline(outline_points, outline_color, outline_width)
