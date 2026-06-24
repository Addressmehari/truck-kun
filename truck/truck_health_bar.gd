extends Node2D

var truck: Node2D
var elapsed_time := 0.0

func _ready() -> void:
	var parent = get_parent()
	while parent:
		if "truck_health" in parent:
			truck = parent
			break
		parent = parent.get_parent()

func _process(delta: float) -> void:
	elapsed_time += delta
	# Keep the health bar perfectly upright regardless of parent's physics rotation!
	global_rotation = 0.0
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(truck) or not ("truck_health" in truck):
		return
		
	var health = truck.get("truck_health")
	var max_health = truck.get("truck_max_health")
	var ratio = clamp(health / max_health, 0.0, 1.0)
	
	# Draw Segmented Retro Arcade Cells (Taller slanted cells matching the event timer)
	var cell_w := 9.0
	var cell_h := 15.0
	var cell_gap := 2.5
	var start_x := -(10.0 * cell_w + 9.0 * cell_gap) / 2.0
	var bar_y := -110.0 # Position above chassis center
	
	# Convert remaining health ratio to a discrete integer cell count (0 to 10)
	var active_cells_count = int(ceil(ratio * 10.0))
	
	# Slant factor (italic tilt matching event timer)
	var slant := -2.0
	# Bold dark outline color for cartoon arcade look
	var outline_color := Color(0.08, 0.08, 0.12)
	var outline_width := 1.5
	
	# Draw backing plate (slightly larger slanted background shadow)
	var plate_w = 10.0 * cell_w + 9.0 * cell_gap + 10.0
	var plate_rect = Rect2(start_x - 5.0, bar_y - 4.0, plate_w, cell_h + 8.0)
	draw_slanted_cell(plate_rect, Color(0.08, 0.08, 0.1, 0.75), Color(0.12, 0.14, 0.16, 0.9), 1.5, slant)
	
	for i in range(10):
		var cell_x = start_x + i * (cell_w + cell_gap)
		var cell_rect = Rect2(cell_x, bar_y, cell_w, cell_h)
		
		# Compute retro warning colors matching the timer: Low health (0-2) Red, Mid (3-6) Yellow, High (7-9) Green
		var cell_color = Color(0.2, 0.85, 0.3) # Green default
		if i < 3:
			cell_color = Color(1.0, 0.25, 0.2) # Red danger zone
		elif i < 7:
			cell_color = Color(0.98, 0.85, 0.1) # Yellow warning zone
			
		# Draw cell background container (dark frame slot)
		var bg_c = Color(0.18, 0.2, 0.25, 0.55)
		draw_slanted_cell(cell_rect, bg_c, outline_color, outline_width, slant)
		
		# Draw active cell highlights
		if i < active_cells_count:
			draw_slanted_cell(cell_rect, cell_color, outline_color, outline_width, slant)
			
	# Draw "TRUCK HP" text label above bar
	var font = ThemeDB.fallback_font
	var text = "TRUCK HEALTH"
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
	var text_pos = Vector2(-text_size.x / 2.0, bar_y - 8.0)
	
	# Draw label shadow
	draw_string(font, text_pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0, 0, 0, 0.95))
	# Draw label text
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.95, 0.95, 0.98))

# Helper function to draw a slanted (italic) vector cell with a bold dark outline
func draw_slanted_cell(rect: Rect2, color: Color, outline_color: Color, outline_width: float, slant: float) -> void:
	var tl = Vector2(rect.position.x + slant, rect.position.y)
	var tr = Vector2(rect.position.x + rect.size.x + slant, rect.position.y)
	var br = Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y)
	var bl = Vector2(rect.position.x, rect.position.y + rect.size.y)
	
	# Filled skewed polygon
	var points = PackedVector2Array([tl, tr, br, bl])
	draw_colored_polygon(points, color)
	
	# Thick, closed outer border line
	var outline_points = PackedVector2Array([tl, tr, br, bl, tl])
	draw_polyline(outline_points, outline_color, outline_width)
