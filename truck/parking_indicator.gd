extends Node2D

var truck: Node2D
var chassis: RigidBody2D
var container_body: RigidBody2D

# Visual properties
var base_radius := 8.0
var ring_width := 1.2

# Fade transitions
var current_alpha: float = 0.0

# Progress bar colors (sleek amber/gold glow)
var progress_color := Color(1.0, 0.65, 0.0, 0.95)
var progress_glow_color := Color(1.0, 0.65, 0.0, 0.3)

func _ready() -> void:
	# Keep upright
	global_rotation = 0.0

func _process(delta: float) -> void:
	if not is_instance_valid(truck) or not is_instance_valid(chassis) or not is_instance_valid(container_body):
		return
		
	# Snappy position switching (no tweening or easing for movement)
	var is_open = truck.has_method("is_zoom_requested") and truck.is_zoom_requested()
	if is_open:
		# Snapped to the opened backdoor ramp area (local coordinates converted to global)
		global_position = container_body.to_global(Vector2(-155.0, -30.0))
	else:
		# Snapped to the top center of the container (local coordinates converted to global)
		global_position = container_body.to_global(Vector2(-61.0, -105.0))
		
	global_rotation = 0.0 # Keep upright
	
	# Determine if the indicator should show
	var speed_kmh = chassis.linear_velocity.length() * 0.08
	var is_parked = truck.current_gear == 0 # 0 is Gear.PARK
	var should_show = (speed_kmh < 20.0 or is_parked)
	
	# Calculate target opacity for fade transitions
	var target_alpha = 0.0
	if should_show:
		if is_parked:
			target_alpha = 1.0 # Full opacity when parked
		else:
			target_alpha = 0.5 # Half opacity normally
			
	# Smoothly fade alpha in/out
	current_alpha = lerp(current_alpha, target_alpha, 12.0 * delta)
	
	# Set visibility threshold
	if current_alpha > 0.01:
		visible = true
	else:
		visible = false
		
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(truck) or current_alpha <= 0.01:
		return
		
	# Base colors modulated by current fade alpha
	var outline_color = Color(1.0, 1.0, 1.0, 0.8 * current_alpha)
	var text_color = Color(1.0, 1.0, 1.0, 0.9 * current_alpha)
	
	# If parked, make outline and text vibrant green modulated by fade alpha
	if truck.current_gear == 0: # 0 is Gear.PARK
		outline_color = Color(0.2, 0.9, 0.4, 0.85 * current_alpha)
		text_color = Color(0.2, 0.9, 0.4, 0.95 * current_alpha)
		
		# Draw solid green background glow ring when parked
		draw_circle_outline(Vector2.ZERO, base_radius, Color(0.2, 0.9, 0.4, 0.45 * current_alpha), ring_width)
		
	# Draw background outline ring
	draw_circle_outline(Vector2.ZERO, base_radius, outline_color, ring_width)
	
	# Draw simple text "O" with visual vertical centering adjustment
	var font = ThemeDB.fallback_font
	var font_size = 9
	var text = "O"
	var string_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	# Center the text baseline: capital letters span [-ascent, 0] with small glyph padding at the top.
	# Shifting baseline down by (ascent / 2.0 - 1.2) aligns the printed glyph center perfectly to Y = 0 for font size 9.
	var text_pos = Vector2(-string_size.x / 2.0, font.get_ascent(font_size) / 2.0 - 1.2)
	draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)
	
	# Draw circular progress bar if holding "O" (progress bar color also modulated by fade alpha)
	if truck.o_hold_time > 0.0:
		var ratio = clamp(truck.o_hold_time / truck.park_hold_threshold, 0.0, 1.0)
		if ratio > 0.0:
			var prg_col = Color(progress_color.r, progress_color.g, progress_color.b, progress_color.a * current_alpha)
			var prg_glow_col = Color(progress_glow_color.r, progress_glow_color.g, progress_glow_color.b, progress_glow_color.a * current_alpha)
			
			# Draw glowing thick outer progress ring
			draw_circle_arc(Vector2.ZERO, base_radius, -PI/2, -PI/2 + (ratio * 2.0 * PI), prg_col, ring_width + 0.5)
			# Draw wider subtle glow behind it
			draw_circle_arc(Vector2.ZERO, base_radius, -PI/2, -PI/2 + (ratio * 2.0 * PI), prg_glow_col, ring_width + 1.5)

# Helper function to draw an outline ring
func draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	draw_arc(center, radius, 0.0, 2.0 * PI, 64, color, width, true)

# Helper function to draw an arc (progress bar)
func draw_circle_arc(center: Vector2, radius: float, angle_from: float, angle_to: float, color: Color, width: float) -> void:
	draw_arc(center, radius, angle_from, angle_to, 64, color, width, true)
