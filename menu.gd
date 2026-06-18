extends Control

@onready var grid_container = $CenterContainer/VBoxContainer/GridContainer
@onready var title_label = $CenterContainer/VBoxContainer/TitleLabel

func _ready() -> void:
	# Ensure fullscreen or correct window size
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	
	# Style the title label with a carved wood / burnt look
	title_label.add_theme_color_override("font_color", Color(0.92, 0.65, 0.35)) # Rich golden wood
	title_label.add_theme_color_override("font_shadow_color", Color(0.12, 0.08, 0.05, 0.8)) # Espresso shadow
	title_label.add_theme_constant_override("shadow_offset_x", 4)
	title_label.add_theme_constant_override("shadow_offset_y", 4)
	
	# Dynamically populate 10 level buttons
	for i in range(1, 11):
		var btn = Button.new()
		btn.text = str(i)
		btn.custom_minimum_size = Vector2(170, 170) # Bigger cell size
		btn.focus_mode = Control.FOCUS_NONE
		
		# Level 1 is unlocked, others are locked
		var is_locked = (i > 1)
		create_button_styles(btn, is_locked)
		
		grid_container.add_child(btn)
		
		# Connect signals for active button
		if not is_locked:
			btn.pressed.connect(_on_level_pressed.bind(i))
			btn.mouse_entered.connect(_on_button_mouse_entered.bind(btn))
			btn.mouse_exited.connect(_on_button_mouse_exited.bind(btn))

func _process(_delta: float) -> void:
	# Gentle swaying rotation for the title label
	if is_instance_valid(title_label):
		title_label.pivot_offset = title_label.size / 2.0
		title_label.rotation = sin(Time.get_ticks_msec() * 0.0025) * 0.02

func _draw() -> void:
	var size_rect = get_viewport_rect().size
	
	# 1. Draw a rich warm wood gradient background
	var points = PackedVector2Array([
		Vector2(0, 0),
		Vector2(size_rect.x, 0),
		Vector2(size_rect.x, size_rect.y),
		Vector2(0, size_rect.y)
	])
	var colors = PackedColorArray([
		Color(0.24, 0.15, 0.10),  # Dark Mahogany
		Color(0.32, 0.20, 0.14),  # Warm Walnut
		Color(0.12, 0.08, 0.05),  # Espresso
		Color(0.16, 0.11, 0.07)   # Deep Cedar
	])
	draw_polygon(points, colors)
	
	# 2. Draw horizontal wood planks/boards lines
	var board_height = 90.0
	var y_pos = board_height
	while y_pos < size_rect.y:
		# Dark shadow crease
		draw_line(Vector2(0, y_pos), Vector2(size_rect.x, y_pos), Color(0.08, 0.05, 0.03, 0.75), 2.0)
		# Warm light highlight below it
		draw_line(Vector2(0, y_pos + 2), Vector2(size_rect.x, y_pos + 2), Color(0.45, 0.35, 0.25, 0.15), 1.5)
		y_pos += board_height

func _on_level_pressed(level_num: int) -> void:
	if level_num == 1:
		get_tree().change_scene_to_file("res://main.tscn")

func _on_button_mouse_entered(btn: Button) -> void:
	btn.pivot_offset = btn.size / 2.0
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(1.1, 1.1), 0.1).set_trans(Tween.TRANS_SINE)

func _on_button_mouse_exited(btn: Button) -> void:
	btn.pivot_offset = btn.size / 2.0
	var tween = create_tween()
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_SINE)

func create_button_styles(btn: Button, is_locked: bool):
	# Base StyleBox with sharp edges (0 corner radius)
	var style_normal = StyleBoxFlat.new()
	style_normal.corner_radius_top_left = 0
	style_normal.corner_radius_top_right = 0
	style_normal.corner_radius_bottom_left = 0
	style_normal.corner_radius_bottom_right = 0
	
	if is_locked:
		# Weathered, grey-brown locked wood
		style_normal.bg_color = Color(0.24, 0.21, 0.18, 0.75)
		style_normal.border_color = Color(0.15, 0.13, 0.11)
		style_normal.border_width_left = 2
		style_normal.border_width_top = 2
		style_normal.border_width_right = 2
		style_normal.border_width_bottom = 6 # 3D flat base
		
		btn.add_theme_stylebox_override("normal", style_normal)
		btn.add_theme_stylebox_override("disabled", style_normal)
		btn.disabled = true
		btn.text = "🔒\nLvl " + btn.text
		btn.add_theme_color_override("font_disabled_color", Color(0.48, 0.44, 0.4, 0.6))
		btn.add_theme_font_size_override("font_size", 22)
	else:
		# Rich Oak wood
		style_normal.bg_color = Color(0.55, 0.38, 0.22)
		style_normal.border_color = Color(0.35, 0.22, 0.1) # Dark brown bevel
		style_normal.border_width_left = 3
		style_normal.border_width_top = 3
		style_normal.border_width_right = 3
		style_normal.border_width_bottom = 10 # 3D extruded bottom face
		
		# Drop shadow
		style_normal.shadow_color = Color(0, 0, 0, 0.4)
		style_normal.shadow_size = 6
		style_normal.shadow_offset = Vector2(0, 6)
		
		# Hover (brighter golden pine wood)
		var style_hover = style_normal.duplicate()
		style_hover.bg_color = Color(0.65, 0.46, 0.28)
		style_hover.border_color = Color(0.45, 0.28, 0.15)
		style_hover.border_width_bottom = 12
		style_hover.shadow_size = 12
		
		# Pressed (pushed down block)
		var style_pressed = style_normal.duplicate()
		style_pressed.bg_color = Color(0.42, 0.28, 0.15)
		style_pressed.border_width_bottom = 3
		style_pressed.shadow_size = 2
		style_pressed.shadow_offset = Vector2(0, 2)
		
		btn.add_theme_stylebox_override("normal", style_normal)
		btn.add_theme_stylebox_override("hover", style_hover)
		btn.add_theme_stylebox_override("pressed", style_pressed)
		
		btn.text = "🚚\nLvl " + btn.text
		btn.add_theme_color_override("font_color", Color(0.98, 0.95, 0.9)) # Cream text
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.95))
		btn.add_theme_font_size_override("font_size", 22)
