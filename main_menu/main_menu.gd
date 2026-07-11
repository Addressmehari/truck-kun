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

var real_truck: Node2D
var click_anim_time: float = -1.0
var beep_bubble_time: float = -1.0
var cheat_buffer: String = ""

# Node references (will be set in ready)
@onready var background_layer = $Background
@onready var play_btn = $UILayout/BottomLayout/HBoxContainer/PlayButtonContainer/PlayButton
@onready var coin_val_label = $UILayout/Header/StatsContainer/CoinBar/Margin/HBox/ValueLabel
@onready var gem_val_label = $UILayout/Header/StatsContainer/GemBar/Margin/HBox/ValueLabel
@onready var highscore_val_label = $UILayout/Header/StatsContainer/HighScoreBar/Margin/HBox/ValueLabel
@onready var coin_bar = $UILayout/Header/StatsContainer/CoinBar
@onready var gem_bar = $UILayout/Header/StatsContainer/GemBar
@onready var highscore_bar = $UILayout/Header/StatsContainer/HighScoreBar
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
	var gem_anchor = $UILayout/Header/StatsContainer/GemBar/Margin/HBox/IconAnchor
	_style_stats_bar(gem_bar)
	gem_anchor.add_child(GemIcon.new())

	var coin_anchor = $UILayout/Header/StatsContainer/CoinBar/Margin/HBox/IconAnchor
	_style_stats_bar(coin_bar)
	coin_anchor.add_child(CoinIcon.new())

	var highscore_bar_node = $UILayout/Header/StatsContainer/HighScoreBar
	var highscore_anchor = $UILayout/Header/StatsContainer/HighScoreBar/Margin/HBox/IconAnchor
	_style_stats_bar(highscore_bar_node)
	highscore_anchor.add_child(TrophyIcon.new())

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

	update_stats_display()
	
	# Connect resize signal to refresh drawing metrics
	get_tree().root.size_changed.connect(queue_redraw)

	# Instance the real truck (Truck-kun) in the main menu
	var truck_scene = load("res://truck/truck.tscn")
	if truck_scene:
		real_truck = truck_scene.instantiate()
		add_child(real_truck)
		move_child(real_truck, 1) # Behind UILayout but in front of Background
		
		# Scale and position
		real_truck.scale = Vector2(3.2, 3.2)
		
		# Remove the gameplay HUD overlay so it doesn't show in the menu
		var hud = real_truck.get_node_or_null("HUD")
		if hud:
			hud.queue_free()
			
		# Disable processing & input handling on the truck
		real_truck.process_mode = Node.PROCESS_MODE_DISABLED
		
		# Freeze all physics bodies so it remains statically suspended
		_freeze_truck_physics(real_truck)
		
		# Enable exhaust smoke particles to float up nicely
		var chassis_node = real_truck.get_node_or_null("chassis")
		if chassis_node:
			for child in chassis_node.get_children():
				if child is CPUParticles2D:
					child.process_mode = Node.PROCESS_MODE_ALWAYS
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

	# Animate and redraw the real instanced truck
	if is_instance_valid(real_truck):
		var target_scale = clamp(screen_size.y / 200.0, 2.0, 3.25)
		
		# --- Process Interactive Jump/Squash Physics ---
		var jump_offset = 0.0
		var scale_modifier = Vector2.ONE
		
		if click_anim_time >= 0.0:
			click_anim_time += delta
			if click_anim_time < 0.15:
				# 1. Prep squish (crouching down slightly)
				var t = click_anim_time / 0.15
				scale_modifier.y = lerp(1.0, 0.97, t)
				scale_modifier.x = lerp(1.0, 1.015, t)
			elif click_anim_time < 0.45:
				# 2. Launch jump
				var t = (click_anim_time - 0.15) / 0.30
				jump_offset = - sin(t * PI) * 25.0
				scale_modifier.y = lerp(0.97, 1.02, sin(t * PI))
				scale_modifier.x = lerp(1.015, 0.985, sin(t * PI))
			elif click_anim_time < 0.65:
				# 3. Falling back down
				var t = (click_anim_time - 0.45) / 0.20
				jump_offset = - cos(t * PI / 2.0) * 6.0 # residual drop height
				scale_modifier.y = lerp(1.02, 0.975, t)
				scale_modifier.x = lerp(0.985, 1.015, t)
			elif click_anim_time < 0.85:
				# 4. Landing squash rebound
				var t = (click_anim_time - 0.65) / 0.20
				scale_modifier.y = lerp(0.975, 1.0, t)
				scale_modifier.x = lerp(1.015, 1.0, t)
			else:
				# Click animation completed
				click_anim_time = -1.0
				
		if beep_bubble_time >= 0.0:
			beep_bubble_time += delta
			if beep_bubble_time > 1.2:
				beep_bubble_time = -1.0
		
		# Set final scale and position combining idle bob and jump offset
		real_truck.scale = Vector2(target_scale * scale_modifier.x, target_scale * scale_modifier.y)
		var bob_offset = Vector2(0.0, sin(elapsed * 5.0) * 5.0)
		real_truck.position = Vector2(screen_size.x / 2.0, screen_size.y / 2.0 + (screen_size.y * 0.05)) + bob_offset + Vector2(0, jump_offset)
		
		# Redraw all truck sub-components
		var tyre1 = real_truck.get_node_or_null("chassis/tyre-1")
		if tyre1:
			tyre1.queue_redraw()
		var tyre2 = real_truck.get_node_or_null("container_body/tyre-2")
		if tyre2:
			tyre2.queue_redraw()
		var tyre3 = real_truck.get_node_or_null("container_body/tyre-3")
		if tyre3:
			tyre3.queue_redraw()
			
		# Subtle engine vibration shake on the cabin (chassis)
		var chassis_node = real_truck.get_node_or_null("chassis")
		if chassis_node:
			chassis_node.position.y = sin(elapsed * 12.0) * 0.8
			chassis_node.queue_redraw()
			
		var container_node = real_truck.get_node_or_null("container_body")
		if container_node:
			container_node.queue_redraw()

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
	if is_instance_valid(highscore_bar):
		highscore_bar.queue_redraw()

	# Trigger redraw for procedural canvas elements
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var key_unicode = event.unicode
		if key_unicode >= 32 and key_unicode <= 126:
			var char_typed = char(key_unicode).to_lower()
			cheat_buffer += char_typed
			if cheat_buffer.length() > 20:
				cheat_buffer = cheat_buffer.substr(cheat_buffer.length() - 20)
			
			if cheat_buffer.ends_with("10kcoins"):
				cheat_buffer = ""
				var gs = get_node_or_null("/root/GameState")
				if gs:
					gs.total_coins += 10000
					gs.save_coins()
					update_stats_display()
					
					var upgrades_menu = get_node_or_null("UpgradesMenu")
					if upgrades_menu and upgrades_menu.has_method("_update_coins_display"):
						upgrades_menu.call("_update_coins_display")
						upgrades_menu.call("_update_rows")
					print("CHEAT: 10,000 Coins added!")

	if not is_instance_valid(real_truck):
		return
		
	var is_click = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var is_touch = event is InputEventScreenTouch and event.pressed
	
	if is_click or is_touch:
		# Convert touch coordinates to truck's local coordinate space
		var local_pos = real_truck.to_local(event.position)
		
		# Truck local bounding box limits:
		# Container starts around x=-119, Cabin ends around x=195. Height is y=-80 to y=65.
		if local_pos.x >= -125.0 and local_pos.x <= 195.0 and local_pos.y >= -85.0 and local_pos.y <= 70.0:
			# Trigger the springy jump and speech bubble if not already animating
			if click_anim_time < 0.0:
				click_anim_time = 0.0
				beep_bubble_time = 0.0
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
	# 1. Draw Rotating Comic Sunburst & Halftone Background
	# ─────────────────────────────────────────────────────────────────
	# Base fill (soft warm browney / latte cream)
	draw_rect(Rect2(Vector2.ZERO, screen_size), Color("#dfd5cd"), true)
	
	var bg_center = screen_size / 2.0
	
	# Draw rotating sunburst rays
	var num_rays = 16
	var ray_angle = TAU / num_rays
	var ray_radius = max(screen_size.x, screen_size.y) * 1.3
	var rotation_angle = elapsed * 0.08 # Smooth rotating speed rays
	
	for i in range(num_rays):
		var a1 = i * ray_angle + rotation_angle
		var a2 = (i + 0.5) * ray_angle + rotation_angle
		
		# Draw alternating colored rays
		if i % 2 == 0:
			var pts_ray = PackedVector2Array([
				bg_center,
				bg_center + Vector2(cos(a1), sin(a1)) * ray_radius,
				bg_center + Vector2(cos(a2), sin(a2)) * ray_radius,
				bg_center
			])
			draw_polygon(pts_ray, PackedColorArray([Color("#c8b7ac")])) # Soft warm tan/cocoa
			
	# Draw pop-art halftone dots (chunky comic grid)
	var grid_spacing = 54.0
	var cols = int(screen_size.x / grid_spacing) + 2
	var rows = int(screen_size.y / grid_spacing) + 2
	for x_idx in range(cols):
		for y_idx in range(rows):
			var pos = Vector2(x_idx * grid_spacing, y_idx * grid_spacing)
			var dist = pos.distance_to(bg_center)
			# Wave pattern for dot sizing (dynamic halftone ripple)
			var rad = 4.0 + sin(elapsed * 2.2 - dist * 0.005) * 2.0
			draw_circle(pos, rad, Color("#ffffff", 0.4))

	# ─────────────────────────────────────────────────────────────────
	# 1.5. Draw Spinning Gears (Garage Theme)
	# ─────────────────────────────────────────────────────────────────
	# --- Top-Left Gear (Behind stats bars) ---
	var gG_center = Vector2(80.0, 80.0)
	_draw_gear(gG_center, 70.0, 7, elapsed * 0.15, Color("#424d5d"))
	
	# --- Top-Right Gear ---
	var gH_center = Vector2(screen_size.x - 80.0, 80.0)
	_draw_gear(gH_center, 80.0, 8, -elapsed * 0.12, Color("#34495e"))

	# --- Bottom-Left Interlocking Chain (3 Gears) ---
	# Bottom-Left Gear A (Large base corner gear)
	var gA_center = Vector2(-20.0, screen_size.y + 20.0)
	_draw_gear(gA_center, 180.0, 14, elapsed * 0.25, Color("#4f5d75"))
	
	# Bottom-Left Gear B (Medium interlocking gear)
	var gB_center = Vector2(170.0, screen_size.y - 110.0)
	_draw_gear(gB_center, 100.0, 8, -elapsed * 0.4375 + 0.35, Color("#708090"))
	
	# Bottom-Left Gear E (Small tertiary gear)
	var gE_center = Vector2(290.0, screen_size.y - 40.0)
	_draw_gear(gE_center, 60.0, 5, elapsed * 0.7 - 0.1, Color("#85929e"))
	
	# --- Bottom-Right Interlocking Chain (3 Gears) ---
	# Bottom-Right Gear C (Large base corner gear)
	var gC_center = Vector2(screen_size.x + 20.0, screen_size.y + 20.0)
	_draw_gear(gC_center, 200.0, 16, -elapsed * 0.2, Color("#566573"))
	
	# Bottom-Right Gear D (Medium interlocking gear)
	var gD_center = Vector2(screen_size.x - 200.0, screen_size.y - 120.0)
	_draw_gear(gD_center, 110.0, 9, elapsed * 0.3556 - 0.2, Color("#4a5868"))
	
	# Bottom-Right Gear F (Small tertiary gear)
	var gF_center = Vector2(screen_size.x - 330.0, screen_size.y - 60.0)
	_draw_gear(gF_center, 70.0, 6, -elapsed * 0.5334 + 0.15, Color("#5d6d7e"))


	# ─────────────────────────────────────────────────────────────────
	# 1.9. Draw Hydraulic Lift & Slab Platform (Garage Theme)
	# ─────────────────────────────────────────────────────────────────
	if is_instance_valid(real_truck):
		# Use stationary (non-squishing, non-jumping) values for the slab
		# so the concrete block stays firmly in place while the truck bobs/jumps
		var t_scale = clamp(screen_size.y / 200.0, 2.0, 3.25)
		var t_pos = Vector2(screen_size.x / 2.0, screen_size.y / 2.0 + (screen_size.y * 0.05)) + Vector2(0.0, sin(elapsed * 5.0) * 5.0)
		
		# --- Calculate landing impact shake ---
		var slab_shake = 0.0
		if click_anim_time >= 0.65 and click_anim_time < 0.85:
			var t_rebound = (click_anim_time - 0.65) / 0.20
			# Heavy dampening wobble
			slab_shake = sin((click_anim_time - 0.65) * 65.0) * 5.0 * (1.0 - t_rebound)
		
		# Center the slab on the midpoint of the truck's wheel span (which is -28px from the truck origin)
		var slab_center_x = t_pos.x - 28.0 * t_scale
		
		# Slab dimensions scaled relative to truck size
		var slab_w = 205.0 * t_scale
		var slab_h = 16.0 * t_scale # Thicker block shape
		var slab_x = slab_center_x - slab_w / 2.0
		# Align slab_y to touch the bottom of the tyres precisely (adding shake)
		var slab_y = t_pos.y + 28.5 * t_scale + slab_shake
		
		# --- A. Draw Hydraulic Pistons (Vertical Pillars) ---
		var piston_left_x = slab_center_x - 55.0 * t_scale
		var piston_right_x = slab_center_x + 55.0 * t_scale
		var piston_width = 9.0 * t_scale
		var piston_color = Color("#7f8c8d") # Metallic silver chrome
		var piston_shadow = Color("#505a5b")
		
		for px in [piston_left_x, piston_right_x]:
			# Piston 3D Shadow (shifted right)
			draw_rect(Rect2(px - piston_width / 2.0 + 8.0, slab_y, piston_width, screen_size.y - slab_y), Color("#0b0512"), true)
			# Piston core
			draw_rect(Rect2(px - piston_width / 2.0, slab_y, piston_width, screen_size.y - slab_y), piston_color, true)
			# Piston inner shading/sheen
			draw_rect(Rect2(px - piston_width / 2.0, slab_y, piston_width * 0.35, screen_size.y - slab_y), Color("#bdc3c7"), true)
			draw_rect(Rect2(px + piston_width * 0.15, slab_y, piston_width * 0.35, screen_size.y - slab_y), piston_shadow, true)
			# Outlines
			draw_line(Vector2(px - piston_width / 2.0, slab_y), Vector2(px - piston_width / 2.0, screen_size.y), Color.BLACK, 4.5)
			draw_line(Vector2(px + piston_width / 2.0, slab_y), Vector2(px + piston_width / 2.0, screen_size.y), Color.BLACK, 4.5)

		# --- B. Draw Concrete Block 3D Drop Shadow ---
		var shadow_offset = Vector2(0.0, 8.0)
		var slab_shadow_pts = PackedVector2Array([
			Vector2(slab_x - 6.0, slab_y + 2.0) + shadow_offset,
			Vector2(slab_x + slab_w + 6.0, slab_y - 2.0) + shadow_offset,
			Vector2(slab_x + slab_w + 3.0, slab_y + slab_h + 3.0) + shadow_offset,
			Vector2(slab_x - 3.0, slab_y + slab_h - 2.0) + shadow_offset
		])
		draw_polygon(slab_shadow_pts, PackedColorArray([Color("#0b0512")]))
		
		# Draw outline for the shadow
		var shadow_outline = PackedVector2Array()
		for pt in slab_shadow_pts:
			shadow_outline.append(pt)
		shadow_outline.append(slab_shadow_pts[0])
		draw_polyline(shadow_outline, Color.BLACK, 6.0)

		# --- C. Draw Concrete Block Core (Wobbly Hand-Drawn Rectangle) ---
		var slab_pts = PackedVector2Array([
			Vector2(slab_x - 6.0, slab_y + 2.0),
			Vector2(slab_x + slab_w + 6.0, slab_y - 2.0),
			Vector2(slab_x + slab_w + 3.0, slab_y + slab_h + 3.0),
			Vector2(slab_x - 3.0, slab_y + slab_h - 2.0)
		])
		# Heavy raw concrete gray color
		draw_polygon(slab_pts, PackedColorArray([Color("#909497")]))
		
		# Inner bevel overlay (for highlights and wobbly hand-drawn texture)
		var slab_inner_pts = PackedVector2Array([
			Vector2(slab_x - 2.0, slab_y + 5.0),
			Vector2(slab_x + slab_w + 2.0, slab_y + 2.0),
			Vector2(slab_x + slab_w, slab_y + slab_h - 2.0),
			Vector2(slab_x + 1.0, slab_y + slab_h - 4.0)
		])
		draw_polygon(slab_inner_pts, PackedColorArray([Color("#a6acaf")]))

		# --- D. Draw Concrete Aggregate Stones (Texture Dots) ---
		var aggregates = [
			Vector2(0.12, 0.35), Vector2(0.24, 0.72), Vector2(0.38, 0.22), Vector2(0.48, 0.82),
			Vector2(0.58, 0.38), Vector2(0.68, 0.76), Vector2(0.78, 0.28), Vector2(0.86, 0.62),
			Vector2(0.94, 0.32), Vector2(0.06, 0.68), Vector2(0.18, 0.52), Vector2(0.88, 0.82)
		]
		for agg in aggregates:
			var ax = slab_x + agg.x * slab_w
			var ay = slab_y + agg.y * slab_h
			draw_circle(Vector2(ax, ay), 2.2, Color("#7f8c8d"))

		# --- E. Draw Concrete Jagged Cracks ---
		# Left-side bottom crack
		var crack1 = PackedVector2Array([
			Vector2(slab_x + 35.0, slab_y + slab_h - 2.0),
			Vector2(slab_x + 48.0, slab_y + slab_h - 14.0),
			Vector2(slab_x + 42.0, slab_y + slab_h - 24.0)
		])
		draw_polyline(crack1, Color.BLACK, 3.0)

		# Right-side top crack
		var crack2 = PackedVector2Array([
			Vector2(slab_x + slab_w - 55.0, slab_y + 1.0),
			Vector2(slab_x + slab_w - 70.0, slab_y + 15.0),
			Vector2(slab_x + slab_w - 65.0, slab_y + 25.0)
		])
		draw_polyline(crack2, Color.BLACK, 3.0)

		# --- F. Draw Outlines ---
		var slab_outline = PackedVector2Array()
		for pt in slab_pts:
			slab_outline.append(pt)
		slab_outline.append(slab_pts[0])
		draw_polyline(slab_outline, Color.BLACK, 6.0)

		# --- G. Draw Comic Horn Speech Bubble ("BEEP! BEEP!") ---
		if beep_bubble_time >= 0.0:
			var truck_pos = real_truck.position
			var truck_scale = real_truck.scale.x
			var truck_scale_y = real_truck.scale.y
			
			# Place bubble above and slightly to the right of the cabin
			var bubble_pos = truck_pos + Vector2(110.0 * truck_scale, -80.0 * truck_scale_y)
			var bubble_w = 60.0 * truck_scale
			var bubble_h = 24.0 * truck_scale_y
			
			# Triangle tail pointing down-left toward the cabin window
			var tail_base_l = bubble_pos + Vector2(-15.0 * truck_scale * 0.45, bubble_h / 2.0)
			var tail_base_r = bubble_pos + Vector2(10.0 * truck_scale * 0.45, bubble_h / 2.0)
			var tail_tip = truck_pos + Vector2(90.0 * truck_scale, -35.0 * truck_scale_y)
			
			var tri_pts = PackedVector2Array([tail_base_l, tail_tip, tail_base_r])
			
			# Speech Bubble Shadow (shifted down-right)
			var s_off = Vector2(0.0, 5.0)
			var tri_shadow = PackedVector2Array([tri_pts[0] + s_off, tri_pts[1] + s_off, tri_pts[2] + s_off])
			
			draw_polygon(tri_shadow, PackedColorArray([Color("#0b0512")]))
			draw_rect(Rect2(bubble_pos - Vector2(bubble_w / 2.0, bubble_h / 2.0) + s_off, Vector2(bubble_w, bubble_h)), Color("#0b0512"), true)
			
			# Speech Bubble Fill (Bright yellow comic-pop)
			draw_polygon(tri_pts, PackedColorArray([Color("#f1c40f")]))
			draw_rect(Rect2(bubble_pos - Vector2(bubble_w / 2.0, bubble_h / 2.0), Vector2(bubble_w, bubble_h)), Color("#f1c40f"), true)
			
			# Black outlines of bubble + pointer tail
			draw_polyline(PackedVector2Array([
				bubble_pos + Vector2(-bubble_w / 2.0, -bubble_h / 2.0),
				bubble_pos + Vector2(bubble_w / 2.0, -bubble_h / 2.0),
				bubble_pos + Vector2(bubble_w / 2.0, bubble_h / 2.0),
				tail_base_r,
				tail_tip,
				tail_base_l,
				bubble_pos + Vector2(-bubble_w / 2.0, bubble_h / 2.0),
				bubble_pos + Vector2(-bubble_w / 2.0, -bubble_h / 2.0)
			]), Color.BLACK, 4.0)
			
			# Comic text "BEEP!"
			var b_text = "BEEP! BEEP!"
			var b_font_size = int(8.0 * truck_scale)
			if b_font_size < 10:
				b_font_size = 10
			var b_font = custom_font if custom_font else get_theme_default_font()
			
			# Draw text outline for legibility
			var b_size = b_font.get_string_size(b_text, HORIZONTAL_ALIGNMENT_CENTER, -1, b_font_size)
			var b_pos = bubble_pos - Vector2(b_size.x / 2.0, -b_font_size * 0.3)
			
			for offset in [Vector2(2, 2), Vector2(-2, 2), Vector2(2, -2), Vector2(-2, -2), Vector2(0, 2), Vector2(0, -2), Vector2(2, 0), Vector2(-2, 0)]:
				draw_string(b_font, b_pos + offset, b_text, HORIZONTAL_ALIGNMENT_LEFT, -1, b_font_size, Color.BLACK)
			# Text fill
			draw_string(b_font, b_pos, b_text, HORIZONTAL_ALIGNMENT_LEFT, -1, b_font_size, Color.WHITE)

	# ─────────────────────────────────────────────────────────────────
	# 2. Draw Falling Leaves (Scaled Up)
	# ─────────────────────────────────────────────────────────────────
	for leaf in leaves:
		_draw_stylized_leaf(leaf)

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

func _style_stats_bar(bar: PanelContainer, plus_btn: Button = null) -> void:
	# Clear default styleboxes so we draw manually
	var empty = StyleBoxEmpty.new()
	bar.add_theme_stylebox_override("panel", empty)
	
	# Connect the draw signal
	if not bar.draw.is_connected(_draw_custom_stats_bar.bind(bar)):
		bar.draw.connect(_draw_custom_stats_bar.bind(bar))
	
	# Style the "+" button
	if plus_btn:
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
	var c0 = Vector2(8.0, 6.0) # Top-left
	var c1 = Vector2(w - 10.0, 4.0) # Top-right
	var c2 = Vector2(w - 6.0, h - 8.0) # Bottom-right
	var c3 = Vector2(10.0, h - 4.0) # Bottom-left
	
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
	var text = "START"
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
	tween.tween_property(btn, "scale", target_scale, 0.12) \
			.set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)

func _on_action_button_pressed(action_name: String) -> void:
	print("Bottom Action Button Tapped: ", action_name)
	if action_name == "X":
		get_tree().quit()
	elif action_name == "⚙️":
		_spawn_settings_menu()
	elif action_name == "🛒":
		_spawn_upgrades_menu()

func _spawn_settings_menu() -> void:
	if has_node("SettingsMenu"):
		return
	var settings_script = load("res://ui/settings_menu.gd")
	if not settings_script:
		push_error("Settings script not found!")
		return
	var menu = CanvasLayer.new()
	menu.set_script(settings_script)
	menu.name = "SettingsMenu"
	add_child(menu)
	menu.call("show_settings")

func _spawn_upgrades_menu() -> void:
	if has_node("UpgradesMenu"):
		return
	var upgrades_script = load("res://ui/upgrades_menu.gd")
	if not upgrades_script:
		push_error("Upgrades script not found!")
		return
	var menu = CanvasLayer.new()
	menu.set_script(upgrades_script)
	menu.name = "UpgradesMenu"
	add_child(menu)
	menu.call("show_upgrades")

func _on_play_hover(is_hover: bool) -> void:
	play_btn.pivot_offset = play_btn.size / 2.0
	var tween = create_tween()
	var target_scale = Vector2(1.18, 1.18) if is_hover else Vector2(1.0, 1.0)
	tween.tween_property(play_btn, "scale", target_scale, 0.12) \
			.set_trans(Tween.TRANS_BACK) \
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

func _draw_gear(center: Vector2, radius: float, teeth_count: int, angle: float, face_color: Color) -> void:
	var depth = radius * 0.15
	var step = TAU / teeth_count
	var pts = PackedVector2Array()
	
	for i in range(teeth_count):
		var a = angle + i * step
		# Corner points of each gear tooth
		var p1 = center + Vector2(cos(a - step * 0.25), sin(a - step * 0.25)) * radius
		var p2 = center + Vector2(cos(a - step * 0.15), sin(a - step * 0.15)) * (radius + depth)
		var p3 = center + Vector2(cos(a + step * 0.15), sin(a + step * 0.15)) * (radius + depth)
		var p4 = center + Vector2(cos(a + step * 0.25), sin(a + step * 0.25)) * radius
		var p5 = center + Vector2(cos(a + step * 0.5), sin(a + step * 0.5)) * (radius - 2.0)
		
		pts.append(p1)
		pts.append(p2)
		pts.append(p3)
		pts.append(p4)
		pts.append(p5)
		
	# Draw outline first (black border, offset/thick)
	var outline_pts = PackedVector2Array()
	for pt in pts:
		outline_pts.append(pt)
	outline_pts.append(pts[0])
	
	# Draw 3D drop shadow of the gear
	var shadow_offset = Vector2(0.0, 8.0)
	var shadow_pts = PackedVector2Array()
	for pt in pts:
		shadow_pts.append(pt + shadow_offset)
	var shadow_outline = PackedVector2Array()
	for pt in shadow_pts:
		shadow_outline.append(pt)
	shadow_outline.append(shadow_pts[0])
	
	draw_polygon(shadow_pts, PackedColorArray([Color("#0b0512")]))
	draw_polyline(shadow_outline, Color.BLACK, 6.0)
	
	# Draw front gear face
	draw_polygon(pts, PackedColorArray([face_color]))
	draw_polyline(outline_pts, Color.BLACK, 6.0)
	
	# Draw 4 circular cutouts inside for mechanical look
	var cutout_dist = radius * 0.58
	var cutout_rad = radius * 0.16
	for j in range(4):
		var ca = angle + j * (PI / 2.0)
		var c_center = center + Vector2(cos(ca), sin(ca)) * cutout_dist
		# Draw outline for cutout
		draw_circle(c_center, cutout_rad, Color.BLACK)
		# Draw fill using base background color to simulate hole
		draw_circle(c_center, cutout_rad - 4.5, Color("#130a1c"))
		
	# Draw central axle hole
	var axle_rad = radius * 0.22
	draw_circle(center, axle_rad, Color.BLACK)
	draw_circle(center, axle_rad - 4.5, Color("#130a1c"))
	# Small center metal pin
	draw_circle(center, axle_rad * 0.4, Color.BLACK)
	draw_circle(center, axle_rad * 0.4 - 2.0, face_color)

# ─────────────────────────────────────────────────────────────────
# Helper Vector Draw Classes for Coin & Gem
# ─────────────────────────────────────────────────────────────────

class CoinIcon extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(38, 38) # Scaled up (was 26)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
	func _draw() -> void:
		var center = size / 2.0
		var r = min(size.x, size.y) / 2.0
		
		# Outermost black border
		draw_circle(center, r, Color.BLACK)
		
		var _color_main = Color(0.88, 0.60, 0.02)
		var _color_inner = Color(1.0, 0.88, 0.28)
		var _color_gem_dark = Color(0.72, 0.44, 0.0)
		var _color_gem_light = Color(1.0, 0.95, 0.6)
		
		# 1. Outer Base Coin Body
		draw_circle(center, r - 1.5, _color_main)

		# 2. Inner Face
		draw_circle(center, r - 5.0, _color_inner)

		# 3. Inner decorative concentric groove ring
		draw_arc(center, r - 8.0, 0.0, TAU, 36, _color_main.lerp(Color.BLACK, 0.1), 1.5)

		# 4. Smooth specular gloss highlight (top-left crescent)
		draw_circle(center - Vector2(r * 0.25, r * 0.25), r * 0.4, Color(1.0, 1.0, 1.0, 0.4))

		# 5. High-contrast crisp outer rim border
		draw_arc(center, r - 2.0, 0.0, TAU, 40, _color_main.lerp(Color.BLACK, 0.4), 2.5)

		# 6. Premium Geometric Inside Design: Layered Diamond Core
		var d_size = r * 0.40
		var d_shadow = Color(0.0, 0.0, 0.0, 0.35)
		
		var d_top = center + Vector2(0, -d_size)
		var d_bottom = center + Vector2(0, d_size)
		var d_left = center + Vector2(-d_size, 0)
		var d_right = center + Vector2(d_size, 0)
		
		# Diamond Shadow Offset
		var s_off = Vector2(0, 1.5)
		draw_colored_polygon(PackedVector2Array([d_top + s_off, d_right + s_off, d_bottom + s_off, d_left + s_off]), d_shadow)
		
		# Diamond Left Facet (Darker shade)
		draw_colored_polygon(PackedVector2Array([d_top, center, d_bottom, d_left]), _color_gem_dark)
		
		# Diamond Right Facet (Lighter shade)
		draw_colored_polygon(PackedVector2Array([d_top, d_right, d_bottom, center]), _color_gem_light)
		
		# Diamond Center Dividing/Border Lines
		var border_color = _color_main.lerp(Color.BLACK, 0.5)
		draw_line(d_top, d_bottom, border_color, 1.5)
		draw_line(d_left, d_right, border_color, 1.5)
		draw_polyline(PackedVector2Array([d_top, d_right, d_bottom, d_left, d_top]), border_color, 2.0)

class GemIcon extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(38, 38) # Scaled up (was 26)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
	func _draw() -> void:
		var center = size / 2.0
		var r = min(size.x, size.y) / 2.0
		
		# Define outer coordinates of diamond gemstone
		var pts = PackedVector2Array([
			center + Vector2(0, -r), # Top
			center + Vector2(r * 0.85, -r * 0.25), # Top Right
			center + Vector2(r * 0.45, r), # Bottom Right
			center + Vector2(-r * 0.45, r), # Bottom Left
			center + Vector2(-r * 0.85, -r * 0.25) # Top Left
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

class TrophyIcon extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(38, 38)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
	func _draw() -> void:
		var center = size / 2.0
		var r = min(size.x, size.y) / 2.0
		
		# Define colors matching the game's premium palette
		var gold_color = Color("#f1c40f")
		var gold_dark = Color("#d4ac0d")
		var gold_light = Color("#f9e79f")
		var border_color = Color.BLACK
		
		# 1. Handles (left and right)
		# Left Handle
		draw_arc(center + Vector2(-r * 0.4, -r * 0.15), r * 0.3, PI/2.0, 3.0 * PI/2.0, 16, border_color, 4.0)
		draw_arc(center + Vector2(-r * 0.4, -r * 0.15), r * 0.3, PI/2.0, 3.0 * PI/2.0, 16, gold_color, 1.8)
		
		# Right Handle
		draw_arc(center + Vector2(r * 0.4, -r * 0.15), r * 0.3, -PI/2.0, PI/2.0, 16, border_color, 4.0)
		draw_arc(center + Vector2(r * 0.4, -r * 0.15), r * 0.3, -PI/2.0, PI/2.0, 16, gold_color, 1.8)
		
		# 2. Base (Trapezoid / Slate base)
		var base_pts = PackedVector2Array([
			center + Vector2(-r * 0.4, r * 0.7),
			center + Vector2(r * 0.4, r * 0.7),
			center + Vector2(r * 0.25, r * 0.45),
			center + Vector2(-r * 0.25, r * 0.45)
		])
		var base_outline = PackedVector2Array()
		for pt in base_pts:
			base_outline.append(pt)
		base_outline.append(base_pts[0])
		
		draw_polygon(base_pts, PackedColorArray([Color("#34495e")])) # Dark slate base
		draw_polyline(base_outline, border_color, 3.5)
		
		# 3. Stem (connector from base to cup)
		var stem_rect = Rect2(center.x - r * 0.1, center.y + r * 0.1, r * 0.2, r * 0.35)
		draw_rect(stem_rect, gold_dark, true)
		draw_rect(stem_rect, border_color, false, 3.5)
		
		# 4. Cup (chalice top)
		var cup_pts = PackedVector2Array([
			center + Vector2(-r * 0.5, -r * 0.6), # Top Left
			center + Vector2(r * 0.5, -r * 0.6),  # Top Right
			center + Vector2(r * 0.4, 0.0),       # Bottom Right
			center + Vector2(0.0, r * 0.25),      # Bottom Center
			center + Vector2(-r * 0.4, 0.0)       # Bottom Left
		])
		
		var cup_outline = PackedVector2Array()
		for pt in cup_pts:
			cup_outline.append(pt)
		cup_outline.append(cup_pts[0])
		
		# Base gold cup fill
		draw_polygon(cup_pts, PackedColorArray([gold_color]))
		
		# Left/Darker shading for 3D depth
		var cup_left_pts = PackedVector2Array([
			center + Vector2(-r * 0.5, -r * 0.6),
			center + Vector2(0.0, -r * 0.6),
			center + Vector2(0.0, r * 0.25),
			center + Vector2(-r * 0.4, 0.0)
		])
		draw_polygon(cup_left_pts, PackedColorArray([gold_dark]))
		
		# Shiny Specular Highlight on the right rim
		var cup_highlight = PackedVector2Array([
			center + Vector2(r * 0.25, -r * 0.5),
			center + Vector2(r * 0.4, -r * 0.5),
			center + Vector2(r * 0.32, -r * 0.1)
		])
		draw_polygon(cup_highlight, PackedColorArray([gold_light]))
		
		# Cup Outer Outline
		draw_polyline(cup_outline, border_color, 4.0)
		
		# Rim inner line (rim opening)
		draw_line(center + Vector2(-r * 0.5, -r * 0.6), center + Vector2(r * 0.5, -r * 0.6), border_color, 3.5)

func _freeze_truck_physics(node: Node) -> void:
	if node is RigidBody2D:
		node.freeze = true
		node.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		# Disable collision elements so they don't block anything
		for child in node.get_children():
			if child is CollisionShape2D or child is CollisionPolygon2D:
				child.disabled = true
	for child in node.get_children():
		_freeze_truck_physics(child)

func update_stats_display() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs:
		coin_val_label.text = str(gs.total_coins)
		gem_val_label.text = str(gs.total_gems)
		highscore_val_label.text = "%d M" % int(gs.best_distance)
	else:
		coin_val_label.text = "0"
		gem_val_label.text = "0"
		highscore_val_label.text = "0 M"

	if custom_font:
		coin_val_label.add_theme_font_override("font", custom_font)
		gem_val_label.add_theme_font_override("font", custom_font)
		highscore_val_label.add_theme_font_override("font", custom_font)
		
	coin_val_label.add_theme_color_override("font_color", Color("#111111"))
	gem_val_label.add_theme_color_override("font_color", Color("#111111"))
	highscore_val_label.add_theme_color_override("font_color", Color("#111111"))
