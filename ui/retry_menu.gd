extends CanvasLayer

## ─── Retry Menu ──────────────────────────────────────────────────────────────
## Shown on player death (crushed / out of fuel / flipped).
## Lets the player retry with a specific seed (0 = random) or return to the main menu.

signal retry_requested(seed_value: int)
signal menu_requested

const FONT_PATH := "res://retro_font.ttf"

var _cause: String = "YOU DIED"
var _distance_m: float = 0.0
var _custom_font: Font = null
var _elapsed: float = 0.0

# UI nodes built in code
var _bg_panel: ColorRect
var _cause_label: Label
var _dist_label: Label
var _seed_label: Label
var _seed_input: LineEdit
var _retry_btn: Button
var _menu_btn: Button

func _ready() -> void:
	layer = 128   # Always on top of HUD

	if ResourceLoader.exists(FONT_PATH):
		_custom_font = load(FONT_PATH)

	_build_ui()
	visible = false   # hidden until show_death() is called

# ── Public API ────────────────────────────────────────────────────────────────

func show_death(cause: String, distance: float) -> void:
	_cause      = cause
	_distance_m = distance
	_cause_label.text = cause
	_dist_label.text  = "DISTANCE:  %d M" % int(distance)
	visible = true
	_animate_in()

# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen dim overlay
	_bg_panel = ColorRect.new()
	_bg_panel.color = Color(0, 0, 0, 0)   # starts transparent, fades in
	_bg_panel.anchor_right  = 1.0
	_bg_panel.anchor_bottom = 1.0
	_bg_panel.mouse_filter  = Control.MOUSE_FILTER_PASS
	add_child(_bg_panel)

	# Centred card
	var card = PanelContainer.new()
	card.name = "Card"
	card.anchor_left   = 0.5
	card.anchor_top    = 0.5
	card.anchor_right  = 0.5
	card.anchor_bottom = 0.5
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical   = Control.GROW_DIRECTION_BOTH
	card.offset_left   = -280.0
	card.offset_top    = -220.0
	card.offset_right  =  280.0
	card.offset_bottom =  220.0
	card.custom_minimum_size = Vector2(560, 440)

	# ── Card background styling ───────────────────────────────────────────────
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.13, 0.08, 0.05)
	panel_style.border_color = Color(0.72, 0.22, 0.08)   # fiery red-orange
	panel_style.border_width_left   = 4
	panel_style.border_width_top    = 4
	panel_style.border_width_right  = 4
	panel_style.border_width_bottom = 4
	panel_style.corner_radius_top_left     = 0
	panel_style.corner_radius_top_right    = 0
	panel_style.corner_radius_bottom_left  = 0
	panel_style.corner_radius_bottom_right = 0
	panel_style.shadow_color  = Color(0.72, 0.12, 0.0, 0.55)
	panel_style.shadow_size   = 18
	panel_style.shadow_offset = Vector2(0, 8)
	card.add_theme_stylebox_override("panel", panel_style)
	add_child(card)

	# Inner vbox
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	card.add_child(vbox)

	# ── Death cause label ─────────────────────────────────────────────────────
	_cause_label = Label.new()
	_cause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cause_label.add_theme_font_size_override("font_size", 52)
	_cause_label.add_theme_color_override("font_color", Color(1.0, 0.22, 0.08))
	_cause_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_cause_label.add_theme_constant_override("outline_size", 8)
	if _custom_font:
		_cause_label.add_theme_font_override("font", _custom_font)
	vbox.add_child(_cause_label)

	# ── Separator ─────────────────────────────────────────────────────────────
	var sep = HSeparator.new()
	var sep_style = StyleBoxFlat.new()
	sep_style.bg_color = Color(0.72, 0.22, 0.08, 0.6)
	sep.add_theme_stylebox_override("separator", sep_style)
	vbox.add_child(sep)

	# ── Distance label ────────────────────────────────────────────────────────
	_dist_label = Label.new()
	_dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dist_label.add_theme_font_size_override("font_size", 28)
	_dist_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6))
	_dist_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_dist_label.add_theme_constant_override("outline_size", 5)
	if _custom_font:
		_dist_label.add_theme_font_override("font", _custom_font)
	vbox.add_child(_dist_label)

	# ── Seed row ──────────────────────────────────────────────────────────────
	var seed_row = HBoxContainer.new()
	seed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	seed_row.add_theme_constant_override("separation", 12)
	vbox.add_child(seed_row)

	_seed_label = Label.new()
	_seed_label.text = "SEED:"
	_seed_label.add_theme_font_size_override("font_size", 22)
	_seed_label.add_theme_color_override("font_color", Color(0.75, 0.65, 0.5))
	if _custom_font:
		_seed_label.add_theme_font_override("font", _custom_font)
	_seed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	seed_row.add_child(_seed_label)

	_seed_input = LineEdit.new()
	_seed_input.placeholder_text = "0  (random)"
	_seed_input.text = "0"
	_seed_input.custom_minimum_size = Vector2(180, 44)
	_seed_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_seed_input.max_length = 10
	# Only allow digits
	var input_style = StyleBoxFlat.new()
	input_style.bg_color = Color(0.08, 0.06, 0.04)
	input_style.border_color = Color(0.55, 0.38, 0.18)
	input_style.border_width_left   = 2
	input_style.border_width_top    = 2
	input_style.border_width_right  = 2
	input_style.border_width_bottom = 4
	input_style.corner_radius_top_left     = 0
	input_style.corner_radius_top_right    = 0
	input_style.corner_radius_bottom_left  = 0
	input_style.corner_radius_bottom_right = 0
	_seed_input.add_theme_stylebox_override("normal", input_style)
	_seed_input.add_theme_stylebox_override("focus", input_style)
	_seed_input.add_theme_color_override("font_color", Color(0.98, 0.92, 0.78))
	_seed_input.add_theme_color_override("font_placeholder_color", Color(0.5, 0.45, 0.35, 0.6))
	_seed_input.add_theme_font_size_override("font_size", 22)
	if _custom_font:
		_seed_input.add_theme_font_override("font", _custom_font)
	seed_row.add_child(_seed_input)

	# ── Button row ────────────────────────────────────────────────────────────
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	vbox.add_child(btn_row)

	_retry_btn = _make_button("🔄  RETRY", Color(0.55, 0.38, 0.22), Color(0.72, 0.52, 0.28))
	_retry_btn.pressed.connect(_on_retry_pressed)
	btn_row.add_child(_retry_btn)

	_menu_btn = _make_button("🏠  MENU", Color(0.22, 0.17, 0.12), Color(0.32, 0.24, 0.16))
	_menu_btn.pressed.connect(_on_menu_pressed)
	btn_row.add_child(_menu_btn)

	# ── Seed hint label ───────────────────────────────────────────────────────
	var hint = Label.new()
	hint.text = "0 = random seed   |   any number = fixed seed"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.5, 0.45, 0.35, 0.75))
	if _custom_font:
		hint.add_theme_font_override("font", _custom_font)
	vbox.add_child(hint)

func _make_button(label: String, base_col: Color, hover_col: Color) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(190, 56)
	btn.focus_mode = Control.FOCUS_NONE

	var style_n = StyleBoxFlat.new()
	style_n.bg_color = base_col
	style_n.border_color = Color(0.35, 0.22, 0.1)
	style_n.border_width_left   = 3
	style_n.border_width_top    = 3
	style_n.border_width_right  = 3
	style_n.border_width_bottom = 9
	style_n.corner_radius_top_left     = 0
	style_n.corner_radius_top_right    = 0
	style_n.corner_radius_bottom_left  = 0
	style_n.corner_radius_bottom_right = 0
	style_n.shadow_color  = Color(0, 0, 0, 0.4)
	style_n.shadow_size   = 6
	style_n.shadow_offset = Vector2(0, 5)

	var style_h = style_n.duplicate()
	style_h.bg_color = hover_col
	style_h.border_width_bottom = 12
	style_h.shadow_size = 12

	var style_p = style_n.duplicate()
	style_p.border_width_bottom = 3
	style_p.shadow_size = 2
	style_p.shadow_offset = Vector2(0, 2)

	btn.add_theme_stylebox_override("normal",  style_n)
	btn.add_theme_stylebox_override("hover",   style_h)
	btn.add_theme_stylebox_override("pressed", style_p)
	btn.add_theme_color_override("font_color",       Color(0.98, 0.95, 0.9))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.95))
	btn.add_theme_font_size_override("font_size", 22)
	if _custom_font:
		btn.add_theme_font_override("font", _custom_font)

	btn.mouse_entered.connect(func():
		var tw = btn.create_tween()
		btn.pivot_offset = btn.size / 2.0
		tw.tween_property(btn, "scale", Vector2(1.08, 1.08), 0.08).set_trans(Tween.TRANS_SINE)
	)
	btn.mouse_exited.connect(func():
		var tw = btn.create_tween()
		btn.pivot_offset = btn.size / 2.0
		tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.08).set_trans(Tween.TRANS_SINE)
	)
	return btn

# ── Animation ─────────────────────────────────────────────────────────────────

func _animate_in() -> void:
	# Fade overlay + slide card down from above
	var card = get_node_or_null("Card")
	if card:
		card.modulate.a = 0.0
		card.offset_top    = -300.0
		card.offset_bottom = -300.0 + 440.0
		var tw = create_tween().set_parallel(true)
		tw.tween_property(_bg_panel, "color:a", 0.65, 0.35)
		tw.tween_property(card, "modulate:a", 1.0, 0.35)
		tw.tween_property(card, "offset_top",    -220.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "offset_bottom",  220.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_bg_panel.color.a = 0.65

# ── Callbacks ─────────────────────────────────────────────────────────────────

func _on_retry_pressed() -> void:
	var raw = _seed_input.text.strip_edges()
	var seed_val := 0
	if raw.is_valid_int():
		seed_val = int(raw)
	retry_requested.emit(seed_val)

func _on_menu_pressed() -> void:
	menu_requested.emit()

# ── Input: filter mouse clicks while visible ──────────────────────────────────
func _input(event: InputEvent) -> void:
	if visible and event is InputEventMouseButton:
		get_viewport().set_input_as_handled()
