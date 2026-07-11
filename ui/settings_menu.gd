extends CanvasLayer

const FONT_PATH: String = "res://retro_font.ttf"
var custom_font: Font

var _title_label: Label
var _main_vbox: VBoxContainer
var _confirm_vbox: VBoxContainer
var _dialog_box: PanelContainer
var _vbox: VBoxContainer

var _music_btn: Button
var _sfx_btn: Button

func _ready() -> void:
	layer = 140 # Topmost overlay
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	# Load the custom retro font
	if ResourceLoader.exists(FONT_PATH):
		custom_font = load(FONT_PATH)
	else:
		custom_font = ThemeDB.get_default_theme().get_default_font()
		push_warning("SettingsMenu: Custom font not found at: " + FONT_PATH)

	# ── Root control (fills the whole screen) ────────────────────────────────
	var root = Control.new()
	root.name = "Control"
	root.anchor_right  = 1.0
	root.anchor_bottom = 1.0
	root.mouse_filter  = Control.MOUSE_FILTER_STOP  # block clicks underneath
	add_child(root)

	# Dark overlay
	var bg = ColorRect.new()
	bg.color            = Color(0.05, 0.03, 0.08, 0.82) # Dark purple tint
	bg.anchor_right     = 1.0
	bg.anchor_bottom    = 1.0
	bg.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	# Centre PanelContainer for Dialog Box
	_dialog_box = PanelContainer.new()
	_dialog_box.name = "DialogBox"
	_dialog_box.anchor_left   = 0.5
	_dialog_box.anchor_top    = 0.5
	_dialog_box.anchor_right  = 0.5
	_dialog_box.anchor_bottom = 0.5
	_dialog_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dialog_box.grow_vertical   = Control.GROW_DIRECTION_BOTH
	_dialog_box.offset_left   = -230.0
	_dialog_box.offset_top    = -230.0
	_dialog_box.offset_right  =  230.0
	_dialog_box.offset_bottom =  230.0
	_dialog_box.pivot_offset  = Vector2(230, 230)
	
	var empty_style = StyleBoxEmpty.new()
	_dialog_box.add_theme_stylebox_override("panel", empty_style)
	_dialog_box.draw.connect(_draw_dialog_panel.bind(_dialog_box))
	root.add_child(_dialog_box)

	# MarginContainer inside Dialog for Padding
	var margin = MarginContainer.new()
	margin.anchor_right  = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 35)
	margin.add_theme_constant_override("margin_top", 35)
	margin.add_theme_constant_override("margin_right", 35)
	margin.add_theme_constant_override("margin_bottom", 35)
	_dialog_box.add_child(margin)

	# ─── State 1: Main Settings VBox ──────────────────────────────────────────
	_main_vbox = VBoxContainer.new()
	_main_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_main_vbox.add_theme_constant_override("separation", 20)
	margin.add_child(_main_vbox)

	# "SETTINGS" title
	_title_label = Label.new()
	_title_label.text = "SETTINGS"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_override("font", custom_font)
	_title_label.add_theme_font_size_override("font_size", 64)
	_title_label.add_theme_color_override("font_color", Color("#f1c40f")) # Bright Yellow
	_title_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_title_label.add_theme_constant_override("outline_size", 8)
	_vbox = _main_vbox # alias for retrocompatibility with feedback adding
	_main_vbox.add_child(_title_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	_main_vbox.add_child(spacer)

	# Music Toggle Button
	_music_btn = Button.new()
	_music_btn.custom_minimum_size = Vector2(250, 58)
	_music_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_music_btn.focus_mode = Control.FOCUS_NONE
	_music_btn.pressed.connect(_on_music_toggled)
	_main_vbox.add_child(_music_btn)
	_update_music_btn_text()
	_style_comic_button(_music_btn, "#3498db", "#2980b9") # Blue

	# SFX Toggle Button
	_sfx_btn = Button.new()
	_sfx_btn.custom_minimum_size = Vector2(250, 58)
	_sfx_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_sfx_btn.focus_mode = Control.FOCUS_NONE
	_sfx_btn.pressed.connect(_on_sfx_toggled)
	_main_vbox.add_child(_sfx_btn)
	_update_sfx_btn_text()
	_style_comic_button(_sfx_btn, "#9b59b6", "#8e44ad") # Purple

	# Reset Progress Button
	var reset_btn = Button.new()
	reset_btn.text = "RESET PROGRESS"
	reset_btn.custom_minimum_size = Vector2(250, 58)
	reset_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.pressed.connect(_show_reset_confirmation)
	_main_vbox.add_child(reset_btn)
	_style_comic_button(reset_btn, "#e74c3c", "#c0392b") # Red

	# Back Button
	var back_btn = Button.new()
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(250, 58)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.pressed.connect(_on_back)
	_main_vbox.add_child(back_btn)
	_style_comic_button(back_btn, "#7f8c8d", "#5f6c6d") # Slate Gray

	# ─── State 2: Confirmation VBox ───────────────────────────────────────────
	_confirm_vbox = VBoxContainer.new()
	_confirm_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm_vbox.add_theme_constant_override("separation", 24)
	_confirm_vbox.visible = false
	margin.add_child(_confirm_vbox)

	var warn_title = Label.new()
	warn_title.text = "ARE YOU SURE?"
	warn_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn_title.add_theme_font_override("font", custom_font)
	warn_title.add_theme_font_size_override("font_size", 48)
	warn_title.add_theme_color_override("font_color", Color("#e74c3c")) # Warning Red
	warn_title.add_theme_color_override("font_outline_color", Color.BLACK)
	warn_title.add_theme_constant_override("outline_size", 8)
	_confirm_vbox.add_child(warn_title)

	var warn_desc = Label.new()
	warn_desc.text = "All coins, gems and distance\nwill be deleted forever!"
	warn_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn_desc.add_theme_font_override("font", custom_font)
	warn_desc.add_theme_font_size_override("font_size", 22)
	warn_desc.add_theme_color_override("font_color", Color.WHITE)
	warn_desc.add_theme_color_override("font_outline_color", Color.BLACK)
	warn_desc.add_theme_constant_override("outline_size", 5)
	_confirm_vbox.add_child(warn_desc)

	# Spacer
	var c_spacer = Control.new()
	c_spacer.custom_minimum_size = Vector2(0, 10)
	_confirm_vbox.add_child(c_spacer)

	# Yes/No buttons in an HBox
	var buttons_hbox = HBoxContainer.new()
	buttons_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons_hbox.add_theme_constant_override("separation", 20)
	_confirm_vbox.add_child(buttons_hbox)

	var yes_btn = Button.new()
	yes_btn.text = "YES, RESET"
	yes_btn.custom_minimum_size = Vector2(170, 58)
	yes_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	yes_btn.focus_mode = Control.FOCUS_NONE
	yes_btn.pressed.connect(_on_confirm_reset)
	buttons_hbox.add_child(yes_btn)
	_style_comic_button(yes_btn, "#e74c3c", "#c0392b") # Red

	var no_btn = Button.new()
	no_btn.text = "NO, CANCEL"
	no_btn.custom_minimum_size = Vector2(170, 58)
	no_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	no_btn.focus_mode = Control.FOCUS_NONE
	no_btn.pressed.connect(_on_cancel_reset)
	buttons_hbox.add_child(no_btn)
	_style_comic_button(no_btn, "#7f8c8d", "#5f6c6d") # Slate Gray

func show_settings() -> void:
	visible = true
	# Pop-in entry animation
	_dialog_box.pivot_offset = _dialog_box.size / 2.0
	_dialog_box.scale = Vector2(0.5, 0.5)
	var tween = create_tween()
	tween.tween_property(_dialog_box, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _update_music_btn_text() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs:
		_music_btn.text = "MUSIC: ON" if gs.music_enabled else "MUSIC: OFF"
		_music_btn.set_meta("btn_text", _music_btn.text)
		_music_btn.queue_redraw()

func _update_sfx_btn_text() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs:
		_sfx_btn.text = "SFX: ON" if gs.sfx_enabled else "SFX: OFF"
		_sfx_btn.set_meta("btn_text", _sfx_btn.text)
		_sfx_btn.queue_redraw()

func _on_music_toggled() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.music_enabled = not gs.music_enabled
		gs.save_coins()
		_update_music_btn_text()

func _on_sfx_toggled() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.sfx_enabled = not gs.sfx_enabled
		gs.save_coins()
		_update_sfx_btn_text()

func _show_reset_confirmation() -> void:
	# Hide main panel and show confirmation screen
	_main_vbox.visible = false
	_confirm_vbox.visible = true
	
	# Small bounce squeeze animation on dialog panel when switching screens
	_dialog_box.pivot_offset = _dialog_box.size / 2.0
	var tween = create_tween()
	tween.tween_property(_dialog_box, "scale", Vector2(1.02, 1.02), 0.08)
	tween.tween_property(_dialog_box, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_BACK)

func _on_cancel_reset() -> void:
	# Return to main view
	_confirm_vbox.visible = false
	_main_vbox.visible = true

func _on_confirm_reset() -> void:
	# Perform the reset
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.reset_progress()
		
		# Update Main Menu stats if it exists
		var main_menu = get_tree().root.get_node_or_null("MainMenu")
		if main_menu and main_menu.has_method("update_stats_display"):
			main_menu.call("update_stats_display")

		# Show flash text feedback inside main view
		_confirm_vbox.visible = false
		_main_vbox.visible = true
		
		var feedback = Label.new()
		feedback.text = "PROGRESS RESET!"
		feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		feedback.add_theme_font_override("font", custom_font)
		feedback.add_theme_font_size_override("font_size", 28)
		feedback.add_theme_color_override("font_color", Color("#e74c3c"))
		feedback.add_theme_color_override("font_outline_color", Color.BLACK)
		feedback.add_theme_constant_override("outline_size", 6)
		_main_vbox.add_child(feedback)
		
		# Position feedback right above back button
		_main_vbox.move_child(feedback, _main_vbox.get_child_count() - 2)
		
		# Fade and queue_free feedback
		var tween = create_tween()
		tween.tween_interval(1.5)
		tween.tween_property(feedback, "modulate:a", 0.0, 0.4)
		tween.tween_callback(feedback.queue_free)

func _on_back() -> void:
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

func _draw_dialog_panel(panel: PanelContainer) -> void:
	if not is_instance_valid(panel):
		return
	var w = panel.size.x
	var h = panel.size.y
	
	var face_color = Color("#1e272e") # Dark gray slate
	var shadow_color = Color("#0f1418") # Deep shadow
	var border_color = Color.BLACK
	
	var shadow_offset = 12.0
	
	# Wobbly panel corners
	var c0 = Vector2(8.0, 8.0)
	var c1 = Vector2(w - 10.0, 7.0)
	var c2 = Vector2(w - 7.0, h - 10.0)
	var c3 = Vector2(10.0, h - 8.0)
	
	# 1. Shadow
	var shadow_pts = PackedVector2Array([
		c0 + Vector2(0, shadow_offset),
		c1 + Vector2(0, shadow_offset),
		c2 + Vector2(0, shadow_offset),
		c3 + Vector2(0, shadow_offset)
	])
	var shadow_outline = PackedVector2Array()
	for pt in shadow_pts:
		shadow_outline.append(pt)
	shadow_outline.append(shadow_pts[0])
	
	panel.draw_polygon(shadow_pts, PackedColorArray([shadow_color]))
	panel.draw_polyline(shadow_outline, border_color, 5.0)
	
	# 2. Front Face
	var face_pts = PackedVector2Array([c0, c1, c2, c3])
	var face_outline = PackedVector2Array()
	for pt in face_pts:
		face_outline.append(pt)
	face_outline.append(face_pts[0])
	
	panel.draw_polygon(face_pts, PackedColorArray([face_color]))
	panel.draw_polyline(face_outline, border_color, 5.0)
	
	# 3. Dynamic highlight line near top border
	var hi_start = c0 + Vector2(16, 6)
	var hi_end = c1 + Vector2(-16, 5)
	panel.draw_line(hi_start, hi_end, Color(1, 1, 1, 0.15), 4.0)

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
