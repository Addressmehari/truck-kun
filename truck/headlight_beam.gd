extends Node2D

@export var enabled: bool = false:
	set(val):
		enabled = val
		queue_redraw()

func _draw() -> void:
	if not enabled:
		return
		
	# Draw the fading light beam polygon
	var beam_len = 150.0
	var beam_width = 130.0
	var beam_poly = PackedVector2Array([
		Vector2.ZERO,
		Vector2(beam_len, -beam_width / 2.0),
		Vector2(beam_len, beam_width / 2.0)
	])
	
	# Softer glowing yellow fading to transparent
	var beam_colors = PackedColorArray([
		Color(1.0, 0.95, 0.65, 0.22), # Soft warm core
		Color(1.0, 0.95, 0.65, 0.0),  # Transparent top edge
		Color(1.0, 0.95, 0.65, 0.0)   # Transparent bottom edge
	])
	
	draw_polygon(beam_poly, beam_colors)
