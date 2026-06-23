extends Control

var event_name: String = ""
var event_icon: String = ""
var duration: float = 15.0
var time_left: float = 15.0
var event_color: Color = Color(0.2, 0.6, 1.0, 0.9)
var is_active := false

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
	
	# Size and positioning relative to anchor center
	offset_left = -160
	offset_right = 160
	offset_top = -70 # Start offscreen
	offset_bottom = -10
	
	# Set name for easy lookup
	name = "EventTimerBar"
	
	# Slide down animation using offsets
	var tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "offset_top", 20.0, 0.5)
	tween.tween_property(self, "offset_bottom", 80.0, 0.5)

func _process(delta: float) -> void:
	if not is_active:
		return
		
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
		
	var truck = get_node_or_null("/root/main/truck")
	if truck and truck.has_method("end_active_event"):
		truck.call("end_active_event", event_name)

	# 4. Restore settings to default (Engine speed scale, etc.)
	Engine.time_scale = 1.0

	# Slide up offscreen using offsets and queue free
	var tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "offset_top", -70.0, 0.4)
	tween.tween_property(self, "offset_bottom", -10.0, 0.4)
	tween.tween_callback(queue_free)

func _draw() -> void:
	# Sleek GTA V HUD backing panel (semi-transparent slate dark color with nice styling)
	var bg_color = Color(0.12, 0.14, 0.18, 0.8)
	var border_color = Color(0.24, 0.28, 0.35, 0.9)
	var rect = Rect2(Vector2.ZERO, size)
	
	# Backing and crisp vector border outline
	draw_rect(rect, bg_color, true)
	draw_rect(rect, border_color, false, 1.5)
	
	# Draw text: Event icon + event name
	var font = get_theme_default_font()
	var font_size = 18
	
	var text_label = event_name.to_upper()
	if event_icon != "":
		text_label = event_icon + "  " + text_label
		
	var text_size = font.get_string_size(text_label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = Vector2((size.x - text_size.x) / 2.0, 35)
	
	# Text shadow
	draw_string(font, text_pos + Vector2(1, 1), text_label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0, 0, 0, 0.6))
	# Main text color (clean off-white)
	draw_string(font, text_pos, text_label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0.95, 0.96, 0.98))
	
	# Shrinking Progress Bar (thin bar on the bottom edge)
	var bar_y := size.y - 5.0
	var bar_height := 4.0
	var progress = time_left / duration
	var bar_width = size.x * progress
	
	# Background track of the bar (dim grey)
	draw_rect(Rect2(0, bar_y, size.x, bar_height), Color(0.22, 0.24, 0.28, 0.5), true)
	# Glowing/filled track (matching event category color)
	draw_rect(Rect2(0, bar_y, bar_width, bar_height), event_color, true)
