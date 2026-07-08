extends Control

# Custom Font
const FONT_PATH: String = "res://retro_font.ttf"
var custom_font: Font

# Falling leaves data structure
class Leaf:
	var base_x: float = 0.0
	var pos: Vector2 = Vector2.ZERO
	var speed: float = 0.0
	var sway_amp: float = 0.0
	var sway_freq: float = 0.0
	var phase: float = 0.0
	var rot: float = 0.0
	var rot_speed: float = 0.0
	var scale: float = 1.0
	var color: Color

var leaves: Array[Leaf] = []
const MAX_LEAVES = 8

# Animation elapsed time
var elapsed: float = 0.0

# Node references (will be set in ready)
@onready var background_layer = $Background
@onready var play_btn = $UILayout/BottomLayout/HBoxContainer/PlayButtonContainer/PlayButton
@onready var coin_val_label = $UILayout/Header/StatsContainer/CoinBar/Margin/HBox/ValueLabel
@onready var gem_val_label = $UILayout/Header/StatsContainer/GemBar/Margin/HBox/ValueLabel
@onready var coin_bar = $UILayout/Header/StatsContainer/CoinBar
@onready var gem_bar = $UILayout/Header/StatsContainer/GemBar
@onready var left_buttons_container = $UILayout/BottomLayout/HBoxContainer/LeftButtons

func _ready() -> void:
	# Load Custom Font
	if ResourceLoader.exists(FONT_PATH):
		custom_font = load(FONT_PATH)
	else:
		custom_font = get_theme_default_font()
		push_warning("Custom font not found at: " + FONT_PATH)

	# Try to set window mode
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	# Initialize falling leaves
	for i in range(MAX_LEAVES):
		leaves.append(create_random_leaf(true))

	# Setup Stat Bars
	var gem_bar = $UILayout/Header/StatsContainer/GemBar
	var gem_plus = $UILayout/Header/StatsContainer/GemBar/Margin/HBox/PlusButton
	var gem_anchor = $UILayout/Header/StatsContainer/GemBar/Margin/HBox/IconAnchor
	_style_stats_bar(gem_bar, gem_plus)
	gem_anchor.add_child(GemIcon.new())

	var coin_bar = $UILayout/Header/StatsContainer/CoinBar
	var coin_plus = $UILayout/Header/StatsContainer/CoinBar/Margin/HBox/PlusButton
	var coin_anchor = $UILayout/Header/StatsContainer/CoinBar/Margin/HBox/IconAnchor
	_style_stats_bar(coin_bar, coin_plus)
	coin_anchor.add_child(CoinIcon.new())

	# Style and wire the Play Button
	if is_instance_valid(play_btn):
		_style_play_button()
		play_btn.mouse_entered.connect(_on_play_hover.bind(true))
		play_btn.mouse_exited.connect(_on_play_hover.bind(false))
		play_btn.pressed.connect(_on_play_pressed)
		# Set pivot to center for nice scale/pulsing
		play_btn.pivot_offset = play_btn.size / 2.0

	# Apply styles and hover triggers to bottom action buttons
	if is_instance_valid(left_buttons_container):
		var index = 0
		for child in left_buttons_container.get_children():
			if child is Button:
				var orig_text = child.text
				_style_action_button(child, index == 4) # 5th button gets the white outline
				child.mouse_entered.connect(_on_action_button_hover.bind(child, true))
				child.mouse_exited.connect(_on_action_button_hover.bind(child, false))
				child.pressed.connect(_on_action_button_pressed.bind(orig_text))
				index += 1

	# Set dynamic stats from game state if available
	var gs = get_node_or_null("/root/GameState")
	if gs:
		coin_val_label.text = str(gs.carryover_coins if gs.carryover_coins > 0 else 25)
	else:
		coin_val_label.text = "25"
	gem_val_label.text = "25" # Gem starting default value

	# Set font and color overrides on labels for readability on light backgrounds
	coin_val_label.add_theme_font_override("font", custom_font)
	gem_val_label.add_theme_font_override("font", custom_font)
	coin_val_label.add_theme_color_override("font_color", Color("#111111"))
	gem_val_label.add_theme_color_override("font_color", Color("#111111"))
	
	# Connect resize signal to refresh drawing metrics
	get_tree().root.size_changed.connect(queue_redraw)

func _process(delta: float) -> void:
	elapsed += delta

	# 1. Update falling leaves
	var screen_size = get_viewport_rect().size
	for leaf in leaves:
		leaf.pos.y += leaf.speed * delta
		leaf.pos.x = leaf.base_x + sin(elapsed * leaf.sway_freq + leaf.phase) * leaf.sway_amp
		leaf.rot += leaf.rot_speed * delta
		
		# Reset when leaf falls off screen
		if leaf.pos.y > screen_size.y + 50 or leaf.pos.x < -50 or leaf.pos.x > screen_size.x + 50:
			var new_leaf = create_random_leaf(false)
			leaf.base_x = new_leaf.base_x
			leaf.pos = new_leaf.pos
			leaf.speed = new_leaf.speed
			leaf.sway_amp = new_leaf.sway_amp
			leaf.sway_freq = new_leaf.sway_freq
			leaf.phase = new_leaf.phase
			leaf.rot = new_leaf.rot
			leaf.rot_speed = new_leaf.rot_speed
			leaf.scale = new_leaf.scale
			leaf.color = new_leaf.color

	# 2. Draw refresh for the PLAY button (pulsing disabled)
	if is_instance_valid(play_btn):
		play_btn.queue_redraw()
		if not play_btn.is_hovered() and not play_btn.is_pressed():
			play_btn.scale = Vector2(1.0, 1.0)

	# Redraw bottom action buttons for custom drawing states
	if is_instance_valid(left_buttons_container):
		for child in left_buttons_container.get_children():
			if child is Button:
				child.queue_redraw()

	if is_instance_valid(coin_bar):
		coin_bar.queue_redraw()
	if is_instance_valid(gem_bar):
		gem_bar.queue_redraw()

	# Trigger redraw for procedural canvas elements
	queue_redraw()

func create_random_leaf(anywhere_y: bool) -> Leaf:
	var leaf = Leaf.new()
	var screen_size = get_viewport_rect().size
	leaf.base_x = randf_range(0, screen_size.x)
	if anywhere_y:
		leaf.pos = Vector2(leaf.base_x, randf_range(-100, screen_size.y))
	else:
		leaf.pos = Vector2(leaf.base_x, -50.0)
	
	leaf.speed = randf_range(50.0, 110.0)
	leaf.sway_amp = randf_range(20.0, 50.0)
	leaf.sway_freq = randf_range(1.0, 2.2)
	leaf.phase = randf_range(0.0, TAU)
	leaf.rot = randf_range(0.0, TAU)
	leaf.rot_speed = randf_range(-1.2, 1.2)
	leaf.scale = randf_range(0.8, 1.4)
	
	# Comic leaf green colors
	var leaf_greens = [
		Color("#8ec03f"),
		Color("#a2d24a"),
		Color("#7cb035"),
		Color("#b5e258")
	]
	leaf.color = leaf_greens[randi() % leaf_greens.size()]
	return leaf

func _draw() -> void:
	var screen_size = get_viewport_rect().size
	
	# ─────────────────────────────────────────────────────────────────
	# 1. Draw Concentric Blue Waves Background
	# ─────────────────────────────────────────────────────────────────
	# Base fill (darkest outer blue)
	draw_rect(Rect2(Vector2.ZERO, screen_size), Color("#1b487c"), true)
	
	var bg_center = screen_size / 2.0
	var base_radius = min(screen_size.x, screen_size.y)
	
	# Pulsing modifiers for dynamic background waves
	var pulse_b = sin(elapsed * 1.5) * 15.0
	var pulse_c = cos(elapsed * 2.0) * 10.0
	var pulse_d = sin(elapsed * 1.0) * 18.0
	
	# Draw concentric rings from outer to inner
	# Ring 1
	draw_circle(bg_center, base_radius * 0.85 + pulse_d, Color("#22558d"))
	# Ring 2
	draw_circle(bg_center, base_radius * 0.65 + pulse_b, Color("#2b65a5"))
	# Ring 3
	draw_circle(bg_center, base_radius * 0.48 + pulse_c, Color("#3676be"))
	# Ring 4
	draw_circle(bg_center, base_radius * 0.32 + pulse_b * 0.5, Color("#4289d7"))
	# Ring 5 (Inner circle center)
	draw_circle(bg_center, base_radius * 0.18 + pulse_c * 0.3, Color("#529cee"))

	# ─────────────────────────────────────────────────────────────────
	# 2. Draw Falling Leaves (Scaled Up)
	# ─────────────────────────────────────────────────────────────────
	for leaf in leaves:
		_draw_stylized_leaf(leaf)

	# ─────────────────────────────────────────────────────────────────
	# 3. Draw Stylized Comic-Style Corner Bushes (Scaled Up)
	# ─────────────────────────────────────────────────────────────────
	_draw_corner_bushes(screen_size)

	# ─────────────────────────────────────────────────────────────────
	# 4. Draw Black Cinematic Letterbox Curved Banners (Top/Bottom)
	# ─────────────────────────────────────────────────────────────────
	_draw_cinematic_letterbox(screen_size)

func _draw_stylized_leaf(leaf: Leaf) -> void:
	# Store the current transform state
	var leaf_transform = Transform2D().translated(leaf.pos).rotated(leaf.rot).scaled(Vector2(leaf.scale, leaf.scale))
	
	# Define points of a larger stylized pointed leaf shape
	var pts = PackedVector2Array([
		Vector2(0, -42),
		Vector2(17, -13),
		Vector2(11, 23),
		Vector2(0, 42),
		Vector2(-11, 23),
		Vector2(-17, -13),
		Vector2(0, -42)
	])
	
	# Map points through local leaf transform
	var final_pts = leaf_transform * pts
	
	# Draw outline first (thick black offset)
	var outline_pts = PackedVector2Array()
	for pt in final_pts:
		outline_pts.append(pt)
	draw_polyline(outline_pts, Color("#0d1804"), 5.5)
	
	# Draw leaf fill
	draw_colored_polygon(final_pts, leaf.color)
	
	# Draw center vein (from base to tip)
	var vein_start = leaf_transform * Vector2(0, 38)
	var vein_end = leaf_transform * Vector2(0, -38)
	draw_line(vein_start, vein_end, Color("#0d1804"), 3.0)

func _draw_corner_bushes(size_rect: Vector2) -> void:
	# Define circles for bottom-left and bottom-right bushes
	# Each circle is described by: offset relative to corner, radius, color
	
	# Green shade constants
	var c_dark = Color("#183b17") # Deep background green
	var c_mid = Color("#295e28")  # Mid-tone green
	var c_light = Color("#4a933f") # Primary leaf green
	var c_bright = Color("#74b84b") # Highlight leaf green
	
	# Bottom-Left Shrub configuration (origins: 0, size_rect.y)
	var bl_corner = Vector2(0, size_rect.y)
	var bl_circles = [
		{"offset": Vector2(30, -30), "rad": 170.0, "color": c_dark},
		{"offset": Vector2(180, -10), "rad": 130.0, "color": c_dark},
		{"offset": Vector2(-20, -110), "rad": 150.0, "color": c_mid},
		{"offset": Vector2(110, -90), "rad": 140.0, "color": c_mid},
		{"offset": Vector2(-40, 20), "rad": 180.0, "color": c_light},
		{"offset": Vector2(50, -30), "rad": 135.0, "color": c_light},
		{"offset": Vector2(140, 50), "rad": 110.0, "color": c_bright}
	]
	
	# Draw Bottom-Left Bush
	for circ in bl_circles:
		var center = bl_corner + circ["offset"]
		# Black outline
		draw_circle(center, circ["rad"], Color("#0b1409"))
		# Green fill
		draw_circle(center, circ["rad"] - 6.5, circ["color"])
		
	# Bottom-Right Shrub configuration (origins: size_rect.x, size_rect.y)
	var br_corner = Vector2(size_rect.x, size_rect.y)
	var br_circles = [
		{"offset": Vector2(-30, -30), "rad": 175.0, "color": c_dark},
		{"offset": Vector2(-180, -10), "rad": 135.0, "color": c_dark},
		{"offset": Vector2(20, -110), "rad": 160.0, "color": c_mid},
		{"offset": Vector2(-110, -90), "rad": 145.0, "color": c_mid},
		{"offset": Vector2(40, 20), "rad": 185.0, "color": c_light},
		{"offset": Vector2(-50, -30), "rad": 140.0, "color": c_light},
		{"offset": Vector2(-140, 50), "rad": 115.0, "color": c_bright}
	]
	
	# Draw Bottom-Right Bush
	for circ in br_circles:
		var center = br_corner + circ["offset"]
		# Black outline
		draw_circle(center, circ["rad"], Color("#0b1409"))
		# Green fill
		draw_circle(center, circ["rad"] - 6.5, circ["color"])

func _draw_cinematic_letterbox(size_rect: Vector2) -> void:
	var segments = 24
	var step = size_rect.x / segments
	
	# --- Top Curved Letterbox Banner ---
	var top_pts = PackedVector2Array()
	top_pts.append(Vector2.ZERO)
	
	# Compute arced bottom edge (increased thickness and curve depth)
	for i in range(segments + 1):
		var x = i * step
		var factor = float(i) / segments
		var y = 85.0 + sin(factor * PI) * 35.0
		top_pts.append(Vector2(x, y))
		
	top_pts.append(Vector2(size_rect.x, 0))
	
	# Draw solid black banner
	draw_colored_polygon(top_pts, Color("#0d0d0d"))
	# Draw outline edge highlight
	var top_line_pts = PackedVector2Array()
	for k in range(1, top_pts.size() - 1):
		top_line_pts.append(top_pts[k])
	draw_polyline(top_line_pts, Color.BLACK, 6.0)

	# --- Bottom Curved Letterbox Banner ---
	var bottom_pts = PackedVector2Array()
	bottom_pts.append(Vector2(0, size_rect.y))
	
	# Compute arced top edge (increased thickness and curve depth)
	for i in range(segments + 1):
		var x = i * step
		var factor = float(i) / segments
		var y = size_rect.y - 95.0 - sin(factor * PI) * 45.0
		bottom_pts.append(Vector2(x, y))
		
	bottom_pts.append(Vector2(size_rect.x, size_rect.y))
	
	# Draw solid black banner
	draw_colored_polygon(bottom_pts, Color("#0d0d0d"))
	# Draw outline edge highlight
	var bottom_line_pts = PackedVector2Array()
	for k in range(1, bottom_pts.size() - 1):
		bottom_line_pts.append(bottom_pts[k])
	draw_polyline(bottom_line_pts, Color.BLACK, 6.0)

# ─────────────────────────────────────────────────────────────────
# 5. UI Custom Styling & Signalling
# ─────────────────────────────────────────────────────────────────

func _style_stats_bar(bar: PanelContainer, plus_btn: Button) -> void:
	# Clear default styleboxes so we draw manually
	var empty = StyleBoxEmpty.new()
	bar.add_theme_stylebox_override("panel", empty)
	
	# Connect the draw signal
	if not bar.draw.is_connected(_draw_custom_stats_bar.bind(bar)):
		bar.draw.connect(_draw_custom_stats_bar.bind(bar))
	
	# Style the "+" button
	var btn_normal = StyleBoxFlat.new()
	btn_normal.bg_color = Color("#d35400")
	btn_normal.border_color = Color.BLACK
	btn_normal.border_width_left = 3
	btn_normal.border_width_top = 3
	btn_normal.border_width_right = 3
	btn_normal.border_width_bottom = 3
	btn_normal.set_corner_radius_all(99) # Circle
	
	var btn_hover = btn_normal.duplicate()
	btn_hover.bg_color = Color("#e67e22") # Bright orange
	
	var btn_pressed = btn_normal.duplicate()
	btn_pressed.bg_color = Color("#a04000")
	
	plus_btn.add_theme_stylebox_override("normal", btn_normal)
	plus_btn.add_theme_stylebox_override("hover", btn_hover)
	plus_btn.add_theme_stylebox_override("pressed", btn_pressed)
	plus_btn.add_theme_stylebox_override("focus", btn_hover)
	plus_btn.add_theme_font_override("font", custom_font)
	plus_btn.add_theme_font_size_override("font_size", 24)
	plus_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	plus_btn.pivot_offset = plus_btn.size / 2.0
	
	# Connect plus button hover animations
	plus_btn.mouse_entered.connect(func():
		var tween = create_tween()
		tween.tween_property(plus_btn, "scale", Vector2(1.2, 1.2), 0.1)
	)
	plus_btn.mouse_exited.connect(func():
		var tween = create_tween()
		tween.tween_property(plus_btn, "scale", Vector2(1.0, 1.0), 0.1)
	)

func _draw_custom_stats_bar(bar: PanelContainer) -> void:
	if not is_instance_valid(bar):
		return
		
	var w = bar.size.x
	var h = bar.size.y
	
	var face_color = Color("#a9cce3") # Pastel sky blue
	var shadow_color = Color("#111111") # Solid black shadow
	var border_color = Color.BLACK
	
	var shadow_offset = 6.0
	
	# Define a wobbly hand-drawn rectangle
	var c0 = Vector2(10.0, 5.0)
	var c1 = Vector2(w - 10.0, 4.0)
	var c2 = Vector2(w - 8.0, h - 8.0)
	var c3 = Vector2(10.0, h - 5.0)
	
	# 1. Draw 3D shadow (bottom layer)
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
	
	bar.draw_polygon(shadow_pts, PackedColorArray([shadow_color]))
	bar.draw_polyline(shadow_outline, border_color, 4.5)
	
	# 2. Draw front face (top layer)
	var face_pts = PackedVector2Array([
		c0,
		c1,
		c2,
		c3
	])
	var face_outline = PackedVector2Array()
	for pt in face_pts:
		face_outline.append(pt)
	face_outline.append(face_pts[0])
	
	bar.draw_polygon(face_pts, PackedColorArray([face_color]))
	bar.draw_polyline(face_outline, border_color, 4.5)
	
	# 3. Draw a highlight line
	var hi_start = c0 + Vector2(12.0, 4.0)
	var hi_end = c1 + Vector2(-12.0, 4.0)
	bar.draw_line(hi_start, hi_end, Color(1, 1, 1, 0.4), 3.5)

func _style_play_button() -> void:
	play_btn.text = "" # Clear text, we draw it customly
	
	# Apply empty styleboxes so default button rendering is disabled
	var empty = StyleBoxEmpty.new()
	play_btn.add_theme_stylebox_override("normal", empty)
	play_btn.add_theme_stylebox_override("hover", empty)
	play_btn.add_theme_stylebox_override("pressed", empty)
	play_btn.add_theme_stylebox_override("focus", empty)
	
	play_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	
	# Connect the draw signal
	if not play_btn.draw.is_connected(_draw_custom_play_button):
		play_btn.draw.connect(_draw_custom_play_button)

func _draw_custom_play_button() -> void:
	if not is_instance_valid(play_btn):
		return
		
	var w = play_btn.size.x
	var h = play_btn.size.y
	
	var is_pressed = play_btn.is_pressed()
	var is_hover = play_btn.is_hovered()
	
	var face_color = Color("#e74c3c") # Red-orange
	var border_color = Color.BLACK
	var shadow_color = Color("#7b241c") # Dark red shadow
	
	var shadow_offset = 12.0
	if is_hover:
		face_color = Color("#ff4d4d") # Brighter red
		shadow_offset = 15.0
	if is_pressed:
		face_color = Color("#b32415") # Darker pressed red
		shadow_offset = 4.0
		
	# Define asymmetrical corner coordinates for an imperfect hand-drawn rectangle
	var c0 = Vector2(8.0, 6.0)        # Top-left
	var c1 = Vector2(w - 10.0, 4.0)   # Top-right
	var c2 = Vector2(w - 6.0, h - 8.0) # Bottom-right
	var c3 = Vector2(10.0, h - 4.0)    # Bottom-left
	
	# 1. Draw the 3D extrusion shadow (bottom layer)
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
	
	play_btn.draw_polygon(shadow_pts, PackedColorArray([shadow_color]))
	play_btn.draw_polyline(shadow_outline, border_color, 7.0) # Thick hand-drawn style outline
	
	# 2. Draw the front face (top layer, offset by state)
	var face_offset = Vector2.ZERO
	if is_pressed:
		face_offset = Vector2(0.0, shadow_offset - 4.0)
		
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
	
	play_btn.draw_polygon(face_pts, PackedColorArray([face_color]))
	play_btn.draw_polyline(face_outline, border_color, 7.0)
	
	# 3. Draw a shiny hand-drawn highlight line at the top
	var hi_start = c0 + Vector2(12.0, 5.0) + face_offset
	var hi_end = c1 + Vector2(-12.0, 5.0) + face_offset
	play_btn.draw_line(hi_start, hi_end, Color("#ffea79", 0.6), 5.0)
	
	# 4. Draw bold comic text "PLAY" centered on the front face
	var text = "PLAY"
	var font_size = 64
	var font = custom_font if custom_font else get_theme_default_font()
	
	# Center calculations using the average center of the face polygon
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var face_center = (c0 + c1 + c2 + c3) / 4.0 + face_offset
	var text_pos = face_center - Vector2(text_size.x / 2.0, -font_size * 0.3)
	
	# Draw thick black text outlines
	for offset in [Vector2(4, 4), Vector2(-4, 4), Vector2(4, -4), Vector2(-4, -4), Vector2(0, 4), Vector2(0, -4), Vector2(4, 0), Vector2(-4, 0)]:
		play_btn.draw_string(font, text_pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
		
	# Draw main white text
	play_btn.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

func _style_action_button(btn: Button, has_white_border: bool) -> void:
	btn.set_meta("emoji", btn.text)
	btn.text = "" # Clear text so we can draw it customly
	
	# Apply empty styleboxes so default button rendering is disabled
	var empty = StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)
	
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pivot_offset = btn.size / 2.0
	
	# Connect the draw signal
	if not btn.draw.is_connected(_draw_custom_action_button):
		btn.draw.connect(_draw_custom_action_button.bind(btn, has_white_border))

func _draw_custom_action_button(btn: Button, has_white_border: bool) -> void:
	if not is_instance_valid(btn):
		return
		
	var w = btn.size.x
	var h = btn.size.y
	
	var is_pressed = btn.is_pressed()
	var is_hover = btn.is_hovered()
	
	var emoji = btn.get_meta("emoji", "")
	
	# Color setup
	var face_color = Color("#313131")
	var shadow_color = Color("#111111")
	var border_color = Color.WHITE if has_white_border else Color.BLACK
	
	# Special coloring for the red Exit button
	if emoji == "X":
		face_color = Color("#e74c3c") # Red-orange
		shadow_color = Color("#7b241c") # Dark red shadow
		
	if is_hover:
		if emoji == "X":
			face_color = Color("#ff4d4d")
		else:
			face_color = Color("#4a4a4a")
			
	if is_pressed:
		if emoji == "X":
			face_color = Color("#b32415")
		else:
			face_color = Color("#1e1e1e")
			
	var shadow_offset = 8.0
	if is_pressed:
		shadow_offset = 3.0
		
	# Define a wobbly hand-drawn square
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
	# Shadow outline is always black
	btn.draw_polyline(shadow_outline, Color.BLACK, 4.5)
	
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
	var hi_color = Color(1, 1, 1, 0.4) if emoji != "X" else Color("#ffea79", 0.6)
	btn.draw_line(hi_start, hi_end, hi_color, 3.5)
	
	# 4. Draw Emoji / Text
	var font_size = 46
	var font = custom_font if custom_font else get_theme_default_font()
	
	var text_size = font.get_string_size(emoji, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var face_center = (c0 + c1 + c2 + c3) / 4.0 + face_offset
	var text_pos = face_center - Vector2(text_size.x / 2.0, -font_size * 0.3)
	
	if emoji == "X":
		# Thick white comic outline around the black text "X"
		for offset in [Vector2(3, 3), Vector2(-3, 3), Vector2(3, -3), Vector2(-3, -3), Vector2(0, 3), Vector2(0, -3), Vector2(3, 0), Vector2(-3, 0)]:
			btn.draw_string(font, text_pos + offset, emoji, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
		btn.draw_string(font, text_pos, emoji, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	else:
		# Standard emoji drop shadow
		btn.draw_string(font, text_pos + Vector2(2, 2), emoji, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.4))
		btn.draw_string(font, text_pos, emoji, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

func _on_action_button_hover(btn: Button, is_hover: bool) -> void:
	btn.pivot_offset = btn.size / 2.0
	var tween = create_tween()
	var target_scale = Vector2(1.12, 1.12) if is_hover else Vector2(1.0, 1.0)
	tween.tween_property(btn, "scale", target_scale, 0.12)\
			.set_trans(Tween.TRANS_BACK)\
			.set_ease(Tween.EASE_OUT)

func _on_action_button_pressed(action_name: String) -> void:
	print("Bottom Action Button Tapped: ", action_name)
	if action_name == "X":
		get_tree().quit()

func _on_play_hover(is_hover: bool) -> void:
	play_btn.pivot_offset = play_btn.size / 2.0
	var tween = create_tween()
	var target_scale = Vector2(1.18, 1.18) if is_hover else Vector2(1.0, 1.0)
	tween.tween_property(play_btn, "scale", target_scale, 0.12)\
			.set_trans(Tween.TRANS_BACK)\
			.set_ease(Tween.EASE_OUT)

func _on_play_pressed() -> void:
	var tween = create_tween()
	tween.tween_property(play_btn, "scale", Vector2(0.9, 0.9), 0.08)
	tween.tween_callback(func():
		var gs = get_node_or_null("/root/GameState")
		if gs:
			gs.transition_to_scene("res://main.tscn")
		else:
			get_tree().change_scene_to_file("res://main.tscn")
	)

# ─────────────────────────────────────────────────────────────────
# Helper Vector Draw Classes for Coin & Gem
# ─────────────────────────────────────────────────────────────────

class CoinIcon extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(38, 38) # Scaled up (was 26)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
	func _draw() -> void:
		var center = size / 2.0
		var rad = min(size.x, size.y) / 2.0
		
		# Outermost outline
		draw_circle(center, rad, Color.BLACK)
		# Outer rim
		draw_circle(center, rad - 3.0, Color("#d4ac0d"))
		# Gold highlight
		draw_circle(center, rad - 5.0, Color("#f1c40f"))
		# Debossed center circle
		draw_circle(center, rad * 0.5, Color("#b7950b"))
		# Specular shine
		draw_circle(center - Vector2(rad * 0.35, rad * 0.35), rad * 0.25, Color.WHITE)

class GemIcon extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(38, 38) # Scaled up (was 26)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
	func _draw() -> void:
		var center = size / 2.0
		var r = min(size.x, size.y) / 2.0
		
		# Define outer coordinates of diamond gemstone
		var pts = PackedVector2Array([
			center + Vector2(0, -r),               # Top
			center + Vector2(r * 0.85, -r * 0.25),  # Top Right
			center + Vector2(r * 0.45, r),          # Bottom Right
			center + Vector2(-r * 0.45, r),         # Bottom Left
			center + Vector2(-r * 0.85, -r * 0.25)  # Top Left
		])
		
		# Base shading
		draw_polygon(pts, PackedColorArray([Color("#2e86c1")]))
		
		# Facet Highlight
		var light_pts = PackedVector2Array([
			center + Vector2(0, -r + 4.0),
			center + Vector2(r * 0.75, -r * 0.25),
			center + Vector2(0, 0)
		])
		draw_polygon(light_pts, PackedColorArray([Color("#a9cce3")]))
		
		# Outlines
		var outline_pts = PackedVector2Array()
		for pt in pts:
			outline_pts.append(pt)
		outline_pts.append(pts[0])
		draw_polyline(outline_pts, Color.BLACK, 4.0)
		
		# Facet line segments
		draw_line(center + Vector2(0, -r), center + Vector2(0, 0), Color.BLACK, 1.8)
		draw_line(center + Vector2(-r * 0.85, -r * 0.25), center + Vector2(0, 0), Color.BLACK, 1.8)
		draw_line(center + Vector2(r * 0.85, -r * 0.25), center + Vector2(0, 0), Color.BLACK, 1.8)
		draw_line(center + Vector2(-r * 0.45, r), center + Vector2(0, 0), Color.BLACK, 1.8)
		draw_line(center + Vector2(r * 0.45, r), center + Vector2(0, 0), Color.BLACK, 1.8)
