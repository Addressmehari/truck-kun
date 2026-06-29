extends Control

# Custom Font Configuration
const FONT_PATH: String = "res://retro_font.ttf"
var custom_font: Font

# Dialogue properties
var dialogue_text: String = ""
var options: Array = []
var metadata: Dictionary = {}

# Size and layout properties
var box_size := Vector2(480, 285)

# References
var label_text: Label
var buttons_container: HBoxContainer

# Opening/closing states for animation
var is_closing := false

func _ready() -> void:
	# Load the custom font safely; fall back to default system font if not found
	if ResourceLoader.exists(FONT_PATH):
		custom_font = load(FONT_PATH)
	else:
		custom_font = get_theme_default_font()
		
	# 1. UI Positioning and Anchors
	custom_minimum_size = box_size
	size = box_size
	
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	
	# Center it on the screen relative to viewport size
	var screen_size = get_viewport_rect().size
	position = (screen_size - box_size) / 2.0
	
	# Keep centered if window size changes
	get_viewport().size_changed.connect(func():
		if is_instance_valid(self) and not is_queued_for_deletion():
			var new_screen = get_viewport_rect().size
			position = (new_screen - box_size) / 2.0
	)
	
	# Set pivot offset for scale animation
	pivot_offset = box_size / 2.0
	
	# 2. Add Layout Container
	var margin = MarginContainer.new()
	margin.anchors_preset = Control.PRESET_FULL_RECT
	margin.anchor_left = 0.0
	margin.anchor_top = 0.0
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.grow_horizontal = Control.GROW_DIRECTION_BOTH
	margin.grow_vertical = Control.GROW_DIRECTION_BOTH
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 25)
	margin.add_child(vbox)
	
	# 3. Dialogue Text Label
	label_text = Label.new()
	label_text.text = dialogue_text
	label_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	label_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Label typography and shadow styling
	label_text.add_theme_font_override("font", custom_font)
	label_text.add_theme_font_size_override("font_size", 22)
	label_text.add_theme_color_override("font_color", Color("#ffffff"))
	label_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label_text.add_theme_constant_override("outline_size", 6)
	vbox.add_child(label_text)
	
	if metadata.get("type") == "delivery_contract":
		# Setup custom content
		label_text.visible = false
		
		# Create a custom VBoxContainer for the details
		var detail_vbox = VBoxContainer.new()
		detail_vbox.alignment = VBoxContainer.ALIGNMENT_CENTER
		detail_vbox.add_theme_constant_override("separation", 20)
		vbox.add_child(detail_vbox)
		vbox.move_child(detail_vbox, 0)
		
		# 1. Title
		var title_lbl = Label.new()
		title_lbl.text = "Delivery"
		title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_lbl.add_theme_font_override("font", custom_font)
		title_lbl.add_theme_font_size_override("font_size", 28)
		title_lbl.add_theme_color_override("font_color", Color("#00f0ff")) # Cyan neon title
		title_lbl.add_theme_constant_override("outline_size", 6)
		detail_vbox.add_child(title_lbl)
		
		# 2. Row 1: Crate and Coin
		var row1 = HBoxContainer.new()
		row1.alignment = HBoxContainer.ALIGNMENT_CENTER
		row1.add_theme_constant_override("separation", 50)
		detail_vbox.add_child(row1)
		
		# Crate part (Icon + text)
		var crate_hbox = HBoxContainer.new()
		crate_hbox.add_theme_constant_override("separation", 10)
		row1.add_child(crate_hbox)
		
		# Crate Icon Control
		var crate_icon = Control.new()
		crate_icon.custom_minimum_size = Vector2(32, 32)
		crate_icon.draw.connect(func():
			var r = Rect2(0, 0, 32, 32)
			crate_icon.draw_rect(r, Color("#e5863c"), true) # Crate wood body
			crate_icon.draw_rect(r, Color("#ab5c20"), false, 2.0) # Outline
			# Inner cross beams
			crate_icon.draw_line(Vector2(4, 4), Vector2(28, 28), Color("#ab5c20"), 2.0)
			crate_icon.draw_line(Vector2(28, 4), Vector2(4, 28), Color("#ab5c20"), 2.0)
		)
		crate_hbox.add_child(crate_icon)
		
		var crate_lbl = Label.new()
		crate_lbl.text = "x%d" % metadata.get("crates", 5)
		crate_lbl.add_theme_font_override("font", custom_font)
		crate_lbl.add_theme_font_size_override("font_size", 22)
		crate_lbl.add_theme_color_override("font_color", Color.WHITE)
		crate_lbl.add_theme_constant_override("outline_size", 4)
		crate_hbox.add_child(crate_lbl)
		
		# Coin part (Icon + text)
		var coin_hbox = HBoxContainer.new()
		coin_hbox.add_theme_constant_override("separation", 10)
		row1.add_child(coin_hbox)
		
		# Coin Icon Control
		var coin_icon = Control.new()
		coin_icon.custom_minimum_size = Vector2(32, 32)
		coin_icon.draw.connect(func():
			var center = Vector2(16, 16)
			coin_icon.draw_circle(center, 14.0, Color("#ffea79", 0.25))
			coin_icon.draw_circle(center, 13.0, Color("#ffb900"))
			coin_icon.draw_circle(center, 8.0, Color("#ffea79"))
			coin_icon.draw_circle(center, 3.0, Color("#ffb900"))
		)
		coin_hbox.add_child(coin_icon)
		
		var coin_lbl = Label.new()
		coin_lbl.text = "%d$" % metadata.get("reward", 1200)
		coin_lbl.add_theme_font_override("font", custom_font)
		coin_lbl.add_theme_font_size_override("font_size", 22)
		coin_lbl.add_theme_color_override("font_color", Color("#ffea79"))
		coin_lbl.add_theme_constant_override("outline_size", 4)
		coin_hbox.add_child(coin_lbl)
		
		# 3. Row 2: Location and Distance
		var row2 = HBoxContainer.new()
		row2.alignment = HBoxContainer.ALIGNMENT_CENTER
		row2.add_theme_constant_override("separation", 10)
		detail_vbox.add_child(row2)
		
		# Location Pin Icon Control
		var pin_icon = Control.new()
		pin_icon.custom_minimum_size = Vector2(24, 32)
		pin_icon.draw.connect(func():
			var center = Vector2(12, 10)
			# Red pin body
			pin_icon.draw_circle(center, 8.0, Color("#ff2a6d"))
			var tri = PackedVector2Array([
				center + Vector2(-8, 2),
				center + Vector2(8, 2),
				center + Vector2(0, 18)
			])
			pin_icon.draw_colored_polygon(tri, Color("#ff2a6d"))
			pin_icon.draw_circle(center, 3.0, Color.WHITE)
		)
		row2.add_child(pin_icon)
		
		var dist_lbl = Label.new()
		dist_lbl.text = "%d meters" % metadata.get("distance", 1800)
		dist_lbl.add_theme_font_override("font", custom_font)
		dist_lbl.add_theme_font_size_override("font_size", 22)
		dist_lbl.add_theme_color_override("font_color", Color.WHITE)
		dist_lbl.add_theme_constant_override("outline_size", 4)
		row2.add_child(dist_lbl)

	# 4. Buttons Container
	buttons_container = HBoxContainer.new()
	buttons_container.alignment = HBoxContainer.ALIGNMENT_CENTER
	buttons_container.add_theme_constant_override("separation", 40)
	vbox.add_child(buttons_container)
	
	# 5. Populate Option Buttons
	for i in range(options.size()):
		var opt = options[i]
		var btn = Button.new()
		btn.text = opt["text"]
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(130, 48)
		
		# Typography
		btn.add_theme_font_override("font", custom_font)
		btn.add_theme_font_size_override("font_size", 20)
		
		# Theme styleboxes to match retro arcade styling
		var style_normal = StyleBoxFlat.new()
		var style_hover = StyleBoxFlat.new()
		var style_pressed = StyleBoxFlat.new()
		
		# Curated neon colors for button borders
		var border_color = Color("#00f0ff") # default cyan
		if opt["text"].to_lower() == "accept":
			border_color = Color("#00e676") # glowing green
		elif opt["text"].to_lower() == "decline":
			border_color = Color("#ff2a6d") # glowing red/pink
		elif opt["text"].to_lower() == "close" or opt["text"].to_lower() == "ok":
			border_color = Color("#ffb900") # gold
			
		style_normal.bg_color = Color(0.05, 0.05, 0.08, 0.85)
		style_normal.border_color = border_color
		style_normal.border_width_left = 2
		style_normal.border_width_top = 2
		style_normal.border_width_right = 2
		style_normal.border_width_bottom = 4
		style_normal.corner_radius_top_left = 6
		style_normal.corner_radius_top_right = 6
		style_normal.corner_radius_bottom_left = 6
		style_normal.corner_radius_bottom_right = 6
		
		style_hover.bg_color = border_color.darkened(0.6)
		style_hover.bg_color.a = 0.8
		style_hover.border_color = border_color
		style_hover.border_width_left = 2
		style_hover.border_width_top = 2
		style_hover.border_width_right = 2
		style_hover.border_width_bottom = 4
		style_hover.corner_radius_top_left = 6
		style_hover.corner_radius_top_right = 6
		style_hover.corner_radius_bottom_left = 6
		style_hover.corner_radius_bottom_right = 6
		
		style_pressed.bg_color = border_color.darkened(0.8)
		style_pressed.border_color = border_color.lightened(0.2)
		style_pressed.border_width_left = 2
		style_pressed.border_width_top = 2
		style_pressed.border_width_right = 2
		style_pressed.border_width_bottom = 2
		style_pressed.corner_radius_top_left = 6
		style_pressed.corner_radius_top_right = 6
		style_pressed.corner_radius_bottom_left = 6
		style_pressed.corner_radius_bottom_right = 6
		
		btn.add_theme_stylebox_override("normal", style_normal)
		btn.add_theme_stylebox_override("hover", style_hover)
		btn.add_theme_stylebox_override("pressed", style_pressed)
		btn.add_theme_color_override("font_color", Color.WHITE)
		btn.add_theme_color_override("font_hover_color", Color.WHITE)
		btn.add_theme_color_override("font_pressed_color", Color.WHITE)
		
		btn.pressed.connect(opt["callback"])
		buttons_container.add_child(btn)
		
	# 6. Play open animation (spring scale-up and fade-in)
	scale = Vector2(0.7, 0.7)
	modulate.a = 0.0
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "modulate:a", 1.0, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func setup(p_text: String, p_options: Array, p_metadata: Dictionary = {}) -> void:
	dialogue_text = p_text
	options = p_options
	metadata = p_metadata

func close_dialogue() -> void:
	if is_closing:
		return
	is_closing = true
	
	# Play close animation (scale-down and fade-out)
	var tween = create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(0.7, 0.7), 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)

func _draw() -> void:
	# Draw Glowing Arcade/Cyberpunk Dialogue frame
	var bg_color = Color(0.05, 0.05, 0.08, 0.90)
	
	# Dynamic color palette to avoid static blue
	var glow_color = Color("#ff2a6d") # Neon hot pink border
	var inner_glow = Color("#00f0ff", 0.3) # Cyan inner accent
	
	if metadata.get("type") == "delivery_contract":
		glow_color = Color("#ffb900") # Neon gold for contracts
		inner_glow = Color("#ff2a6d", 0.4) # Hot pink inner accent
		
	var box_rect = Rect2(Vector2.ZERO, box_size)
	
	# Draw shadow
	draw_rect(box_rect.grow(4), Color(0, 0, 0, 0.35), false, 4.0)
	
	# Draw background
	draw_rect(box_rect, bg_color, true)
	
	# Draw double glowing borders
	draw_rect(box_rect, glow_color, false, 3.0)
	draw_rect(box_rect.grow(-3.0), inner_glow, false, 1.5)
