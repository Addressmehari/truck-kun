extends Control

var start_x := 0.0
var end_x := 0.0
var crusher_xs: Array = []
var is_active := false
var elapsed_time := 0.0

# Cached references for optimization
var _road: Node2D = null

func _get_active_player_body() -> Node2D:
	var truck = get_node_or_null("/root/main/truck")
	if is_instance_valid(truck):
		if truck.get("is_water_mode_active") and is_instance_valid(truck.get("boat")):
			return truck.get("boat")
		elif is_instance_valid(truck.get("chassis")):
			return truck.get("chassis")
	return null

func setup(p_start_x: float, p_end_x: float, p_crusher_xs: Array) -> void:
	start_x = p_start_x
	end_x = p_end_x
	crusher_xs = p_crusher_xs
	is_active = true
	elapsed_time = 0.0
	
	# Cache road reference once during setup
	_road = get_node_or_null("/root/main/Road")
	
	# Set layout anchors to top center (matching EventTimerBar)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.0
	anchor_bottom = 0.0
	grow_horizontal = GROW_DIRECTION_BOTH
	grow_vertical = GROW_DIRECTION_END
	
	# Match EventTimerBar dimensions (580px wide, 130px tall)
	offset_left = -290
	offset_right = 290
	offset_top = -140 # Start offscreen
	offset_bottom = -10
	
	name = "CrusherProgressBar"
	
	# Slide down animation using offsets
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "offset_top", 20.0, 0.5)
	tween.tween_property(self, "offset_bottom", 150.0, 0.5)

func _physics_process(delta: float) -> void:
	if not is_active:
		return
		
	elapsed_time += delta
	
	var active_body = _get_active_player_body()
	if is_instance_valid(active_body):
		var current_x = active_body.global_position.x
		
		# Slide the UI away when player clears the last crusher
		if current_x >= end_x and offset_top > -130:
			var tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
			tween.tween_property(self, "offset_top", -140.0, 0.4)
			tween.tween_property(self, "offset_bottom", -10.0, 0.4)
			offset_top = -140
			
		# Reset road flattening only when player is fully past the 400px hilly transition zone
		if current_x >= end_x + 500.0:
			is_active = false
			if is_instance_valid(_road):
				_road.set("crusher_flat_start_x", 0.0)
				_road.set("crusher_flat_end_x", 0.0)
				if _road.has_method("regenerate_runtime_chunks"):
					_road.call("regenerate_runtime_chunks")
			end_event()
			
	queue_redraw()

func end_event() -> void:
	# Clean up any active treadmills in the scene
	for t in get_tree().get_nodes_in_group("treadmills"):
		t.queue_free()
	queue_free()

func _draw() -> void:
	# Get player X for current progress calculation
	var current_x = start_x
	var active_body = _get_active_player_body()
	if is_instance_valid(active_body):
		current_x = active_body.global_position.x
	
	# Draw title: "⚠️  CRUSHER GAUNTLET  ⚠️"
	var font = get_theme_default_font()
	var font_size = 28
	var title_text = "⚠️  CRUSHER GAUNTLET  ⚠️"
	var text_size = font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_bob = cos(elapsed_time * 4.0) * 2.0
	var text_pos = Vector2((size.x - text_size.x) / 2.0, 38 + text_bob)
	
	# Text shadow then main text
	draw_string(font, text_pos + Vector2(2, 2), title_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0, 0, 0, 0.85))
	draw_string(font, text_pos, title_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0.95, 0.96, 0.98))
	
	# Layout properties matching EventTimerBar style
	var num_cells: int = crusher_xs.size()
	var cell_w: float = 44.0
	var cell_h: float = 55.0
	var cell_gap: float = 8.0
	var start_x_pos: float = (size.x - (num_cells * cell_w + (num_cells - 1) * cell_gap)) / 2.0
	var bar_y: float = 60.0
	var slant: float = -6.0
	var outline_color: Color = Color(0.08, 0.08, 0.12)
	var outline_width: float = 3.0
	
	# Draw the slanted cells
	for i in range(num_cells):
		# Spring spawn scale animation (EASE_OUT_BACK overshoot) matching EventTimerBar
		var t = elapsed_time - 0.4 - (i * 0.05)
		var cell_scale = 0.0
		if t > 0.0:
			var dur = 0.35
			if t < dur:
				var x_val = (t / dur) - 1.0
				cell_scale = x_val * x_val * (2.70158 * x_val + 1.70158) + 1.0
			else:
				cell_scale = 1.0
				
		if cell_scale <= 0.01:
			continue
			
		# Funky bobbing wave animation matching EventTimerBar
		var bob = sin(elapsed_time * 6.0 + i * 0.75) * 4.0
		
		# Center coordinates for scaling
		var cell_center_x = start_x_pos + i * (cell_w + cell_gap) + cell_w / 2.0
		var cell_center_y = bar_y + cell_h / 2.0
		
		var curr_w = cell_w * cell_scale
		var curr_h = cell_h * cell_scale
		var cell_rect = Rect2(cell_center_x - curr_w / 2.0, cell_center_y - curr_h / 2.0, curr_w, curr_h)
		
		# Determine retro warning color based on cell position ratio
		var ratio: float = float(i) / max(1.0, float(num_cells - 1))
		var cell_color := Color(0.2, 0.85, 0.3) # Green default
		if ratio > 0.7:
			cell_color = Color(1.0, 0.25, 0.2) # Red danger zone
		elif ratio > 0.35:
			cell_color = Color(0.98, 0.85, 0.1) # Yellow warning zone
			
		# Draw cell background container (dimmed warning color slot)
		var bg_c = cell_color * 0.22
		bg_c.a = 0.55
		draw_slanted_cell(cell_rect, bg_c, outline_color, outline_width, slant, bob)
		
		# Highlight active cells with their bright warning color as player crosses each crusher
		if current_x > crusher_xs[i]:
			draw_slanted_cell(cell_rect, cell_color, outline_color, outline_width, slant, bob)

# Helper function to draw a slanted vector cell (identical to EventTimerBar)
func draw_slanted_cell(rect: Rect2, color: Color, outline_color: Color, outline_width: float, slant_val: float, bob: float) -> void:
	var tl = Vector2(rect.position.x + slant_val, rect.position.y + bob)
	var tr = Vector2(rect.position.x + rect.size.x + slant_val, rect.position.y + bob)
	var br = Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y + bob)
	var bl = Vector2(rect.position.x, rect.position.y + rect.size.y + bob)
	
	var points = PackedVector2Array([tl, tr, br, bl])
	draw_colored_polygon(points, color)
	
	var outline_points = PackedVector2Array([tl, tr, br, bl, tl])
	draw_polyline(outline_points, outline_color, outline_width)
