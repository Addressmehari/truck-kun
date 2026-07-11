extends CanvasLayer

const FONT_PATH: String = "res://retro_font.ttf"
var custom_font: Font

var _title_label: Label
var _coins_label: Label
var _main_panel: PanelContainer
var _cards_hbox: HBoxContainer

# Tracking nodes for dynamic updates
var _card_buttons: Dictionary = {}
var _level_grids: Dictionary = {}

const UPGRADE_COSTS = [150, 300, 600, 1200]

func _ready() -> void:
	layer = 140 # Topmost overlay
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	# Load the custom retro font
	if ResourceLoader.exists(FONT_PATH):
		custom_font = load(FONT_PATH)
	else:
		custom_font = ThemeDB.get_default_theme().get_default_font()
		push_warning("UpgradesMenu: Custom font not found at: " + FONT_PATH)

	# ── Root control (fills the whole screen) ────────────────────────────────
	var root = Control.new()
	root.name = "Control"
	root.anchor_right  = 1.0
	root.anchor_bottom = 1.0
	root.mouse_filter  = Control.MOUSE_FILTER_PASS  # PASS so we don't block clicks on the truck in the top half!
	add_child(root)

	# Let's add a darker transparent band at the bottom to hold the panel
	var bg_shadow = ColorRect.new()
	bg_shadow.color = Color(0, 0, 0, 0.4)
	bg_shadow.anchor_left = 0.0
	bg_shadow.anchor_top = 0.63
	bg_shadow.anchor_right = 1.0
	bg_shadow.anchor_bottom = 1.0
	bg_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg_shadow)

	# Main bottom panel container
	_main_panel = PanelContainer.new()
	_main_panel.name = "MainPanel"
	_main_panel.anchor_left   = 0.0
	_main_panel.anchor_top    = 0.65
	_main_panel.anchor_right  = 1.0
	_main_panel.anchor_bottom = 1.0
	_main_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_main_panel.grow_vertical   = Control.GROW_DIRECTION_BOTH
	_main_panel.offset_left   = 40.0
	_main_panel.offset_top    = 0.0
	_main_panel.offset_right  = -40.0
	_main_panel.offset_bottom = -25.0
	
	var empty_style = StyleBoxEmpty.new()
	_main_panel.add_theme_stylebox_override("panel", empty_style)
	_main_panel.draw.connect(_draw_main_panel.bind(_main_panel))
	root.add_child(_main_panel)

	# MarginContainer for spacing inside bottom panel
	var margin = MarginContainer.new()
	margin.anchor_right  = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 20)
	_main_panel.add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15)
	margin.add_child(main_vbox)

	# Header HBox (Title, Coins, and Back Button)
	var header_hbox = HBoxContainer.new()
	header_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(header_hbox)

	# Title
	_title_label = Label.new()
	_title_label.text = "GARAGE UPGRADES"
	_title_label.add_theme_font_override("font", custom_font)
	_title_label.add_theme_font_size_override("font_size", 34)
	_title_label.add_theme_color_override("font_color", Color("#f1c40f")) # Yellow
	_title_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_title_label.add_theme_constant_override("outline_size", 8)
	header_hbox.add_child(_title_label)

	# Spacer between title and coins
	var h_spacer1 = Control.new()
	h_spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(h_spacer1)

	# Coin indicator
	_coins_label = Label.new()
	_coins_label.add_theme_font_override("font", custom_font)
	_coins_label.add_theme_font_size_override("font_size", 28)
	_coins_label.add_theme_color_override("font_color", Color("#2ecc71")) # Green
	_coins_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_coins_label.add_theme_constant_override("outline_size", 6)
	header_hbox.add_child(_coins_label)
	_update_coins_display()

	# Spacer between coins and back
	var h_spacer2 = Control.new()
	h_spacer2.custom_minimum_size = Vector2(40, 0)
	header_hbox.add_child(h_spacer2)

	# Back Button
	var back_btn = Button.new()
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(140, 42)
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.pressed.connect(_on_back)
	header_hbox.add_child(back_btn)
	_style_comic_button(back_btn, "#7f8c8d", "#5f6c6d") # Slate Gray

	# Horizontal Cards List
	_cards_hbox = HBoxContainer.new()
	_cards_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_hbox.add_theme_constant_override("separation", 24)
	_cards_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(_cards_hbox)

	# Create the 4 upgrade cards
	_create_upgrade_card("engine", "ENGINE", "🚀", "#3498db", "#2980b9")
	_create_upgrade_card("fuel", "FUEL TANK", "⛽", "#e67e22", "#d35400")
	_create_upgrade_card("air", "TILT CONTROL", "🕹️", "#9b59b6", "#8e44ad")
	_create_upgrade_card("shield", "SHIELD", "🛡️", "#e74c3c", "#c0392b")

func show_upgrades() -> void:
	visible = true
	_update_coins_display()
	_update_rows()
	
	# Slide-up entry animation from bottom
	_main_panel.pivot_offset = Vector2(_main_panel.size.x / 2.0, _main_panel.size.y)
	var final_y = _main_panel.position.y
	_main_panel.position.y += 500.0
	
	var tween = create_tween()
	tween.tween_property(_main_panel, "position:y", final_y, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _update_coins_display() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs:
		_coins_label.text = "COINS: %d 🪙" % gs.total_coins

func _create_upgrade_card(type: String, title: String, emoji: String, face_hex: String, shadow_hex: String) -> void:
	# Card PanelContainer (styled wobbly panel)
	var card = PanelContainer.new()
	card.custom_minimum_size = Vector2(220, 210)
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	card.draw.connect(_draw_card_panel.bind(card, face_hex))
	_cards_hbox.add_child(card)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)

	var card_vbox = VBoxContainer.new()
	card_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(card_vbox)

	# Emoji Icon
	var icon_lbl = Label.new()
	icon_lbl.text = emoji
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 30)
	card_vbox.add_child(icon_lbl)

	# Title
	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_override("font", custom_font)
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	title_lbl.add_theme_constant_override("outline_size", 4)
	card_vbox.add_child(title_lbl)

	# Level blocks display (5 blocks)
	var level_hbox = HBoxContainer.new()
	level_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	level_hbox.add_theme_constant_override("separation", 6)
	card_vbox.add_child(level_hbox)
	
	# Cache level grid nodes
	var blocks_list = []
	for i in range(5):
		var block = Control.new()
		block.custom_minimum_size = Vector2(18, 8)
		block.draw.connect(_draw_level_block.bind(block, i, type))
		level_hbox.add_child(block)
		blocks_list.append(block)
		
	_level_grids[type] = blocks_list

	# Spacer
	var c_spacer = Control.new()
	c_spacer.custom_minimum_size = Vector2(0, 2)
	card_vbox.add_child(c_spacer)

	# Purchase Button
	var btn = Button.new()
	btn.custom_minimum_size = Vector2(150, 38)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_upgrade_pressed.bind(type))
	card_vbox.add_child(btn)
	_style_comic_button(btn, face_hex, shadow_hex)
	_card_buttons[type] = btn

func _draw_level_block(block: Control, index: int, type: String) -> void:
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return
		
	var lvl = gs.get(type + "_level")
	var is_filled = (index < lvl)
	
	var w = block.size.x
	var h = block.size.y
	
	# Draw background
	var color = Color("#f1c40f") if is_filled else Color("#7f8c8d").darkened(0.2)
	var border = Color.BLACK
	
	# Draw wobbly box
	var pts = PackedVector2Array([
		Vector2(2.0, 1.0),
		Vector2(w - 2.0, 2.0),
		Vector2(w - 1.0, h - 2.0),
		Vector2(1.0, h - 1.0)
	])
	var outline = PackedVector2Array()
	for pt in pts:
		outline.append(pt)
	outline.append(pts[0])
	
	block.draw_polygon(pts, PackedColorArray([color]))
	block.draw_polyline(outline, border, 2.0)

func _draw_card_panel(panel: PanelContainer, face_color_hex: String) -> void:
	var w = panel.size.x
	var h = panel.size.y
	
	var face_color = Color(face_color_hex).darkened(0.55) # Darkened card back for contrast
	var shadow_color = Color.BLACK
	var shadow_offset = 6.0
	
	var c0 = Vector2(5.0, 5.0)
	var c1 = Vector2(w - 6.0, 4.0)
	var c2 = Vector2(w - 4.0, h - 6.0)
	var c3 = Vector2(6.0, h - 5.0)
	
	# Shadow
	var shadow_pts = PackedVector2Array([
		c0 + Vector2(0, shadow_offset),
		c1 + Vector2(0, shadow_offset),
		c2 + Vector2(0, shadow_offset),
		c3 + Vector2(0, shadow_offset)
	])
	panel.draw_polygon(shadow_pts, PackedColorArray([shadow_color]))
	
	# Face
	var face_pts = PackedVector2Array([c0, c1, c2, c3])
	var face_outline = PackedVector2Array()
	for pt in face_pts:
		face_outline.append(pt)
	face_outline.append(face_pts[0])
	
	panel.draw_polygon(face_pts, PackedColorArray([face_color]))
	panel.draw_polyline(face_outline, Color.BLACK, 3.5)

func _update_rows() -> void:
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return

	for type in ["engine", "fuel", "air", "shield"]:
		var current_lvl = gs.get(type + "_level")
		var btn = _card_buttons[type]
		var blocks_list = _level_grids[type]

		# Force level blocks redraw
		for block in blocks_list:
			block.queue_redraw()
		
		# Update Button Cost/Text
		if current_lvl >= 5:
			btn.text = "MAXED OUT"
			btn.disabled = true
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		else:
			var cost = UPGRADE_COSTS[current_lvl - 1]
			btn.text = "%d 🪙" % cost
			btn.disabled = (gs.total_coins < cost)
			if btn.disabled:
				btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
			else:
				btn.mouse_filter = Control.MOUSE_FILTER_STOP

		btn.set_meta("btn_text", btn.text)
		btn.queue_redraw()

func _on_upgrade_pressed(type: String) -> void:
	var gs = get_node_or_null("/root/GameState")
	if not gs:
		return

	var current_lvl = gs.get(type + "_level")
	if current_lvl >= 5:
		return

	var cost = UPGRADE_COSTS[current_lvl - 1]
	if gs.total_coins >= cost:
		gs.total_coins -= cost
		gs.set(type + "_level", current_lvl + 1)
		gs.save_coins()
		
		# Juice animation on the card box
		var card = _card_buttons[type].get_parent().get_parent() # Button -> VBox -> MarginContainer -> Card
		card.pivot_offset = card.size / 2.0
		var tween = create_tween()
		tween.tween_property(card, "scale", Vector2(1.05, 1.05), 0.08)
		tween.tween_property(card, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_BACK)

		# Refresh
		_update_coins_display()
		_update_rows()

		# Update Main Menu stats if it exists
		var main_menu = get_tree().root.get_node_or_null("MainMenu")
		if main_menu and main_menu.has_method("update_stats_display"):
			main_menu.call("update_stats_display")

func _on_back() -> void:
	# Update Main Menu stats if it exists
	var main_menu = get_tree().root.get_node_or_null("MainMenu")
	if main_menu and main_menu.has_method("update_stats_display"):
		main_menu.call("update_stats_display")
	queue_free()

func _style_comic_button(btn: Button, face_color_hex: String, shadow_color_hex: String) -> void:
	btn.set_meta("btn_text", btn.text)
	btn.text = "" # Clear default text as we draw it customly
	
	var empty = StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)
	btn.add_theme_stylebox_override("disabled", empty)
	
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pivot_offset = btn.custom_minimum_size / 2.0
	
	if not btn.draw.is_connected(_draw_custom_button.bind(btn, face_color_hex, shadow_color_hex)):
		btn.draw.connect(_draw_custom_button.bind(btn, face_color_hex, shadow_color_hex))

	btn.mouse_entered.connect(func():
		if btn.disabled: return
		var tween = create_tween()
		tween.tween_property(btn, "scale", Vector2(1.1, 1.1), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)
	btn.mouse_exited.connect(func():
		if btn.disabled: return
		var tween = create_tween()
		tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	)

func _draw_main_panel(panel: PanelContainer) -> void:
	if not is_instance_valid(panel):
		return
	var w = panel.size.x
	var h = panel.size.y
	
	var face_color = Color("#1e272e") # Dark slate
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
	var is_disabled = btn.disabled
	
	var text = btn.get_meta("btn_text", "")
	
	var base_face = Color(face_color_hex)
	var base_shadow = Color(shadow_color_hex)
	
	if is_disabled:
		base_face = Color("#7f8c8d").darkened(0.2) # gray out disabled
		base_shadow = Color("#7f8c8d").darkened(0.4)
		
	var face_color = base_face
	var shadow_color = base_shadow
	var border_color = Color.BLACK
	
	var shadow_offset = 8.0
	if is_hover and not is_disabled:
		face_color = base_face.lightened(0.15)
		shadow_offset = 10.0
	if is_pressed and not is_disabled:
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
	if is_pressed and not is_disabled:
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
	
	# 3. Draw a highlight line (skip if disabled to look flat)
	if not is_disabled:
		var hi_start = c0 + Vector2(10.0, 4.0) + face_offset
		var hi_end = c1 + Vector2(-10.0, 4.0) + face_offset
		btn.draw_line(hi_start, hi_end, Color(1, 1, 1, 0.4), 3.5)
	
	# 4. Draw Text
	var font_size = 18
	var font = custom_font if custom_font else ThemeDB.get_default_theme().get_default_font()
	
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var face_center = (c0 + c1 + c2 + c3) / 4.0 + face_offset
	var text_pos = face_center - Vector2(text_size.x / 2.0, -font_size * 0.3)
	
	# Thick outline around text
	var text_color = Color.WHITE if not is_disabled else Color("#bdc3c7")
	for offset in [Vector2(2, 2), Vector2(-2, 2), Vector2(2, -2), Vector2(-2, -2), Vector2(0, 2), Vector2(0, -2), Vector2(2, 0), Vector2(-2, 0)]:
		btn.draw_string(font, text_pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	btn.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
