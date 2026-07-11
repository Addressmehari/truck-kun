extends CanvasLayer

var _cause_label: Label

func _ready() -> void:
	layer = 128
	visible = false

	# ── Root control (fills the whole screen) ────────────────────────────────
	var root = Control.new()
	root.anchor_right  = 1.0
	root.anchor_bottom = 1.0
	root.mouse_filter  = Control.MOUSE_FILTER_STOP  # block clicks underneath
	add_child(root)

	# Dark overlay
	var bg = ColorRect.new()
	bg.color            = Color(0, 0, 0, 0.75)
	bg.anchor_right     = 1.0
	bg.anchor_bottom    = 1.0
	bg.mouse_filter     = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

	# Centre VBox
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.anchor_left   = 0.5
	vbox.anchor_top    = 0.5
	vbox.anchor_right  = 0.5
	vbox.anchor_bottom = 0.5
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.grow_vertical   = Control.GROW_DIRECTION_BOTH
	vbox.offset_left   = -160.0
	vbox.offset_top    = -70.0
	vbox.offset_right  =  160.0
	vbox.offset_bottom =  70.0
	vbox.add_theme_constant_override("separation", 24)
	root.add_child(vbox)

	# Death cause label
	_cause_label = Label.new()
	_cause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cause_label.add_theme_font_size_override("font_size", 48)
	_cause_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.1))
	_cause_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_cause_label.add_theme_constant_override("outline_size", 6)
	vbox.add_child(_cause_label)

	# Retry button
	var btn = Button.new()
	btn.text = "RETRY"
	btn.custom_minimum_size = Vector2(160, 52)
	btn.focus_mode = Control.FOCUS_NONE
	var sty = StyleBoxFlat.new()
	sty.bg_color     = Color(0.55, 0.35, 0.15)
	sty.border_color = Color(0.85, 0.55, 0.25)
	sty.set_border_width_all(2)
	sty.border_width_bottom = 6
	btn.add_theme_stylebox_override("normal", sty)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 24)
	btn.pressed.connect(_on_retry)
	vbox.add_child(btn)

	# Main Menu button
	var menu_btn = Button.new()
	menu_btn.text = "MAIN MENU"
	menu_btn.custom_minimum_size = Vector2(160, 52)
	menu_btn.focus_mode = Control.FOCUS_NONE
	var menu_sty = sty.duplicate()
	menu_btn.add_theme_stylebox_override("normal", menu_sty)
	menu_btn.add_theme_color_override("font_color", Color.WHITE)
	menu_btn.add_theme_font_size_override("font_size", 24)
	menu_btn.pressed.connect(_on_main_menu)
	vbox.add_child(menu_btn)

func show_death(cause: String, _distance: float) -> void:
	_cause_label.text = cause
	visible = true

func _on_retry() -> void:
	visible = false
	# Write a fresh random seed into GameState before reloading
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

