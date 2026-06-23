extends Node2D

@onready var truck = get_parent()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(truck) or not ("truck_health" in truck):
		return
		
	var health = truck.get("truck_health")
	var max_health = truck.get("truck_max_health")
	var ratio = clamp(health / max_health, 0.0, 1.0)
	
	var bar_w := 120.0
	var bar_h := 10.0
	var pos = Vector2(-bar_w / 2.0, -110.0) # Position above chassis center
	
	# Draw background plate (translucent dark border)
	draw_rect(Rect2(pos - Vector2(3, 3), Vector2(bar_w + 6, bar_h + 6)), Color(0.08, 0.08, 0.1, 0.75), true)
	draw_rect(Rect2(pos - Vector2(3, 3), Vector2(bar_w + 6, bar_h + 6)), Color(0.12, 0.14, 0.16, 0.9), false, 1.5)
	
	# Health Bar Background (dark red/gray empty bar)
	draw_rect(Rect2(pos, Vector2(bar_w, bar_h)), Color(0.22, 0.08, 0.08, 0.95), true)
	
	# Health Bar Fill
	var fill_color = Color(0.25, 0.92, 0.35) # Vibrant Green
	if ratio < 0.3:
		fill_color = Color(0.95, 0.15, 0.15) # Red danger
	elif ratio < 0.65:
		fill_color = Color(0.98, 0.85, 0.1) # Yellow warning
		
	draw_rect(Rect2(pos, Vector2(bar_w * ratio, bar_h)), fill_color, true)
	
	# Light highlight reflection on health bar
	draw_line(pos + Vector2(0, 2), pos + Vector2(bar_w * ratio, 2), Color(1.0, 1.0, 1.0, 0.3), 1.0)
	
	# Draw "HEALTH" or "TRUCK HP" text label above bar
	var font = ThemeDB.fallback_font
	var text = "TRUCK HEALTH"
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10)
	var text_pos = Vector2(-text_size.x / 2.0, pos.y - 6.0)
	
	# Draw label shadow
	draw_string(font, text_pos + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0, 0, 0, 0.95))
	# Draw label text
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, 10, Color(0.95, 0.95, 0.98))
