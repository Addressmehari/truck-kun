extends CanvasLayer

const FONT_PATH: String = "res://retro_font.ttf"
var custom_font: Font

var _title_label: Label
var _vbox: VBoxContainer

func _ready() -> void:
	layer = 130 # Higher than retry menu
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	# Load the custom retro font
	if ResourceLoader.exists(FONT_PATH):
		custom_font = load(FONT_PATH)
	else:
		custom_font = ThemeDB.get_default_theme().get_default_font()
		push_warning("PauseMenu: Custom font not found at: " + FONT_PATH)

	# ── Root control (fills the whole screen) ────────────────────────────────
	var root = Control.new()
	root.anchor_right  = 1.0
	root.anchor_bottom = 1.0
	root.mouse_filter  = Control.MOUSE_FILTER_STOP  # block clicks underneath
	add_child(root)

	# Dark overlay
	var bg = ColorRect.new()
	bg.color            = Color(0, 0, 0, 0.78)
	bg.anchor_right     = 1.0
	bg.anchor_bottom    = 1.0
	bg.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	# Centre VBox
	_vbox = VBoxContainer.new()
	_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_vbox.anchor_left   = 0.5
	_vbox.anchor_top    = 0.5
	_vbox.anchor_right  = 0.5
	_vbox.anchor_bottom = 0.5
	_vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_vbox.grow_vertical   = Control.GROW_DIRECTION_BOTH
	_vbox.offset_left   = -200.0
	_vbox.offset_top    = -180.0
	_vbox.offset_right  =  200.0
	_vbox.offset_bottom =  180.0
	_vbox.add_theme_constant_override("separation", 24)
	root.add_child(_vbox)

	# "PAUSED" title
	_title_label = Label.new()
	_title_label.text = "PAUSED"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_override("font", custom_font)
	_title_label.add_theme_font_size_override("font_size", 64)
	_title_label.add_theme_color_override("font_color", Color("#e74c3c")) # Bright Red
	_title_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_title_label.add_theme_constant_override("outline_size", 8)
	_vbox.add_child(_title_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	_vbox.add_child(spacer)

	# Resume button
	var resume_btn = Button.new()
	resume_btn.text = "RESUME"
	resume_btn.custom_minimum_size = Vector2(220, 58)
	resume_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	resume_btn.focus_mode = Control.FOCUS_NONE
	resume_btn.pressed.connect(_on_resume)
	_vbox.add_child(resume_btn)
	_style_comic_button(resume_btn, "#2ecc71", "#27ae60") # Premium Green

	# Restart button
	var restart_btn = Button.new()
	restart_btn.text = "RESTART"
	restart_btn.custom_minimum_size = Vector2(220, 58)
	restart_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	restart_btn.focus_mode = Control.FOCUS_NONE
	restart_btn.pressed.connect(_on_restart)
	_vbox.add_child(restart_btn)
	_style_comic_button(restart_btn, "#e67e22", "#d35400") # Retro Orange

	# Main Menu button
	var menu_btn = Button.new()
	menu_btn.text = "MAIN MENU"
	menu_btn.custom_minimum_size = Vector2(220, 58)
	menu_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.pressed.connect(_on_main_menu)
	_vbox.add_child(menu_btn)
	_style_comic_button(menu_btn, "#34495e", "#2c3e50") # Slate Gray

func show_pause() -> void:
	get_tree().paused = true
	visible = true

	# Pop-in entry animation
	_vbox.pivot_offset = _vbox.size / 2.0
	_vbox.scale = Vector2(0.5, 0.5)
	var tween = create_tween()
	tween.tween_property(_vbox, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_resume()

func _on_resume() -> void:
	get_tree().paused = false
	queue_free()

func _on_restart() -> void:
	get_tree().paused = false
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.pending_road_seed = randi()
		gs.is_continuing = false
		gs.carryover_coins = 0
		gs.carryover_distance_m = 0.0
		gs.transition_to_scene("res://main.tscn")
	else:
		get_tree().change_scene_to_file("res://main.tscn")
	queue_free()

func _on_main_menu() -> void:
	get_tree().paused = false
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.is_continuing = false
		gs.carryover_coins = 0
		gs.carryover_distance_m = 0.0
		gs.transition_to_scene("res://main_menu/main_menu.tscn")
	else:
		get_tree().change_scene_to_file("res://main_menu/main_menu.tscn")
	queue_free()

func _style_comic_button(btn: Button, face_color_hex: String, shadow_color_hex: String) -> void:
	btn.set_meta("btn_text", btn.text)
	btn.text = "" # Clear default text as we draw it customly
	
	var empty = StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)
	
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pivot_offset = btn.custom_minimum_size / 2.0
	
	if not btn.draw.is_connected(_draw_custom_button.bind(btn, face_color_hex, shadow_color_hex)):
		btn.draw.connect(_draw_custom_button.bind(btn, face_color_hex, shadow_color_hex))

	btn.mouse_entered.connect(func():
		var tween = create_tween()
		tween.tween_property(btn, "scale", Vector2(1.1, 1.1), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)
	btn.mouse_exited.connect(func():
		var tween = create_tween()
		tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)

func _draw_custom_button(btn: Button, face_color_hex: String, shadow_color_hex: String) -> void:
	if not is_instance_valid(btn):
		return
		
	var w = btn.size.x
	var h = btn.size.y
	
	var is_pressed = btn.is_pressed()
	var is_hover = btn.is_hovered()
	
	var text = btn.get_meta("btn_text", "")
	
	var base_face = Color(face_color_hex)
	var base_shadow = Color(shadow_color_hex)
	
	var face_color = base_face
	var shadow_color = base_shadow
	var border_color = Color.BLACK
	
	var shadow_offset = 8.0
	if is_hover:
		face_color = base_face.lightened(0.15)
		shadow_offset = 10.0
	if is_pressed:
		face_color = base_face.darkened(0.2)
		shadow_offset = 3.0
		
	# Asymmetrical corner coordinates for wobbly comic design
	var c0 = Vector2(6.0, 5.0)
	var c1 = Vector2(w - 7.0, 4.0)
	var c2 = Vector2(w - 5.0, h - 7.0)
	var c3 = Vector2(7.0, h - 5.0)
	
	# 1. Draw 3D shadow
	var shadow_pts = PackedVector2Array([
		c0 + Vector2(0.0, shadow_offset),
		c1 + Vector2(0.0, shadow_offset),
		c2 + Vector2(0.0, shadow_offset),
		c3 + Vector2(0.0, shadow_offset)
	])
	var shadow_outline = PackedVector2Array()
	for pt in shadow_pts:
		shadow_outline.append(pt)
	shadow_outline.append(shadow_pts[0])
	
	btn.draw_polygon(shadow_pts, PackedColorArray([shadow_color]))
	btn.draw_polyline(shadow_outline, border_color, 4.5)
	
	# 2. Draw front face
	var face_offset = Vector2.ZERO
	if is_pressed:
		face_offset = Vector2(0.0, shadow_offset - 3.0)
		
	var face_pts = PackedVector2Array([
		c0 + face_offset,
		c1 + face_offset,
		c2 + face_offset,
		c3 + face_offset
	])
	var face_outline = PackedVector2Array()
	for pt in face_pts:
		face_outline.append(pt)
	face_outline.append(face_pts[0])
	
	btn.draw_polygon(face_pts, PackedColorArray([face_color]))
	btn.draw_polyline(face_outline, border_color, 4.5)
	
	# 3. Draw a highlight line
	var hi_start = c0 + Vector2(10.0, 4.0) + face_offset
	var hi_end = c1 + Vector2(-10.0, 4.0) + face_offset
	btn.draw_line(hi_start, hi_end, Color(1, 1, 1, 0.4), 3.5)
	
	# 4. Draw Text
	var font_size = 24
	var font = custom_font if custom_font else ThemeDB.get_default_theme().get_default_font()
	
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var face_center = (c0 + c1 + c2 + c3) / 4.0 + face_offset
	var text_pos = face_center - Vector2(text_size.x / 2.0, -font_size * 0.3)
	
	# Thick outline around text
	for offset in [Vector2(2, 2), Vector2(-2, 2), Vector2(2, -2), Vector2(-2, -2), Vector2(0, 2), Vector2(0, -2), Vector2(2, 0), Vector2(-2, 0)]:
		btn.draw_string(font, text_pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	btn.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
