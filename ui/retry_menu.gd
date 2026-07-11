extends CanvasLayer

const FONT_PATH: String = "res://retro_font.ttf"
var custom_font: Font

var _cause_label: Label
var _distance_label: Label
var _vbox: VBoxContainer

func _ready() -> void:
	layer = 128
	visible = false

	# Load the custom retro font
	if ResourceLoader.exists(FONT_PATH):
		custom_font = load(FONT_PATH)
	else:
		custom_font = get_theme_default_font()
		push_warning("RetryMenu: Custom font not found at: " + FONT_PATH)

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
	_vbox.offset_top    = -150.0
	_vbox.offset_right  =  200.0
	_vbox.offset_bottom =  150.0
	_vbox.add_theme_constant_override("separation", 24)
	root.add_child(_vbox)

	# Title / Death cause label
	_cause_label = Label.new()
	_cause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cause_label.add_theme_font_override("font", custom_font)
	_cause_label.add_theme_font_size_override("font_size", 54)
	_cause_label.add_theme_color_override("font_color", Color("#e74c3c")) # Bright Red
	_cause_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_cause_label.add_theme_constant_override("outline_size", 8)
	_vbox.add_child(_cause_label)

	# Distance label
	_distance_label = Label.new()
	_distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_distance_label.add_theme_font_override("font", custom_font)
	_distance_label.add_theme_font_size_override("font_size", 34)
	_distance_label.add_theme_color_override("font_color", Color("#f1c40f")) # Gold
	_distance_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_distance_label.add_theme_constant_override("outline_size", 6)
	_vbox.add_child(_distance_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	_vbox.add_child(spacer)

	# Retry button
	var btn = Button.new()
	btn.text = "RETRY"
	btn.custom_minimum_size = Vector2(220, 58)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_retry)
	_vbox.add_child(btn)
	# Style RETRY with a bright, retro orange face
	_style_comic_button(btn, "#e67e22", "#d35400")

	# Main Menu button
	var menu_btn = Button.new()
	menu_btn.text = "MAIN MENU"
	menu_btn.custom_minimum_size = Vector2(220, 58)
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.pressed.connect(_on_main_menu)
	_vbox.add_child(menu_btn)
	# Style MAIN MENU with a sleek slate gray face
	_style_comic_button(menu_btn, "#34495e", "#2c3e50")

func show_death(cause: String, distance: float) -> void:
	_cause_label.text = cause.upper()
	_distance_label.text = "DISTANCE: %d M" % int(distance)
	visible = true

	# Add a juice entry animation (scale pop) to the vbox on death
	_vbox.pivot_offset = _vbox.size / 2.0
	_vbox.scale = Vector2(0.5, 0.5)
	var tween = create_tween()
	tween.tween_property(_vbox, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

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
	var font = custom_font if custom_font else get_theme_default_font()
	
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var face_center = (c0 + c1 + c2 + c3) / 4.0 + face_offset
	var text_pos = face_center - Vector2(text_size.x / 2.0, -font_size * 0.3)
	
	# Thick outline around text
	for offset in [Vector2(2, 2), Vector2(-2, 2), Vector2(2, -2), Vector2(-2, -2), Vector2(0, 2), Vector2(0, -2), Vector2(2, 0), Vector2(-2, 0)]:
		btn.draw_string(font, text_pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	btn.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

func _on_retry() -> void:
	visible = false
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.pending_road_seed = randi()
		gs.is_continuing = false
		gs.carryover_coins = 0
		gs.carryover_distance_m = 0.0
		gs.transition_to_scene("res://main.tscn")
	else:
		get_tree().change_scene_to_file("res://main.tscn")

func _on_main_menu() -> void:
	visible = false
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.is_continuing = false
		gs.carryover_coins = 0
		gs.carryover_distance_m = 0.0
		gs.transition_to_scene("res://main_menu/main_menu.tscn")
	else:
		get_tree().change_scene_to_file("res://main_menu/main_menu.tscn")
