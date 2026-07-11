extends Control

# Custom Font Configuration
const FONT_PATH: String = "res://retro_font.ttf" # Change this to your exact font file path
const SAVE_PATH: String = "user://highscore.cfg"

var custom_font: Font

# Public State
var coins: int = 0
var _coin_pop_timer: float = 0.0
var _coin_pop_scale: float = 1.0
var gems: int = 0
var _gem_pop_timer: float = 0.0
var _last_gem_amount: int = 1

# Petrol State
var petrol: float = 100.0        # 0–100
var petrol_max: float = 100.0
var _petrol_fill_timer: float = 0.0  # animation when refilled
var _petrol_fill_amount: float = 0.0

# Internal
var chassis: RigidBody2D
var _start_x: float = 0.0
var _distance_m: float = 0.0
var _distance_offset_m: float = 0.0
var _best_distance_m: float = 0.0

# Animation
var _elapsed: float = 0.0
var _dist_bump_timer: float = 0.0
var _last_milestone: int = 0
var _last_coin_amount: int = 1

# Arcade flicker/pulse
var _coin_digit_flash: float = 0.0
var _streak_timer: float = 0.0
var _streak_shown: bool = false
var _best_beaten_active: bool = false

func _ready() -> void:
	await get_tree().process_frame

	# Load the custom font safely; fall back to default if not found
	if ResourceLoader.exists(FONT_PATH):
		custom_font = load(FONT_PATH)
	else:
		push_warning("Custom font not found at: " + FONT_PATH + ". Using default system font.")
		custom_font = get_theme_default_font()

	var hud = get_parent()
	var truck = hud.get_parent() if hud else null
	if truck:
		chassis = truck.get_node_or_null("chassis")

	if is_instance_valid(chassis):
		_start_x = chassis.global_position.x

	# Load best distance from persistent save file
	load_best_distance()

	# Apply carryover statistics from GameState if transitioning to Silhouette Mode
	var gs = get_node_or_null("/root/GameState")
	if gs and gs.is_continuing:
		coins = gs.carryover_coins
		_distance_offset_m = gs.carryover_distance_m
		_distance_m = _distance_offset_m
		gs.is_continuing = false

	# Apply Fuel Tank Upgrade
	if gs:
		var fuel_lvl = gs.get("fuel_level") if gs.get("fuel_level") != null else 1
		petrol_max = 100.0 + (fuel_lvl - 1) * 25.0 # Up to 200.0 max at Level 5
		petrol = petrol_max

	# ── Responsive Safe-Zone Setup (1.2x Enlarged Layout) ─────────────
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.5
	anchor_bottom = 0.4
	
	offset_left = 38.0  # 32.0 * 1.2
	offset_top = 38.0   # 32.0 * 1.2
	offset_right = 0.0
	offset_bottom = 0.0

func save_best_distance() -> void:
	var config = ConfigFile.new()
	config.set_value("progression", "best_distance", _best_distance_m)
	config.save(SAVE_PATH)

func load_best_distance() -> void:
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		_best_distance_m = config.get_value("progression", "best_distance", 0.0)

func _process(delta: float) -> void:
	_elapsed += delta

	if is_instance_valid(chassis):
		var raw = (chassis.global_position.x - _start_x) / 30.0 + _distance_offset_m
		_distance_m = max(_distance_m, raw)
		if _distance_m > _best_distance_m:
			# Show milestone pop-up ONLY when high score is beaten
			if _best_distance_m > 0.0 and not _best_beaten_active:
				_best_beaten_active = true
				_streak_timer = 1.5
				_streak_shown = true
				_dist_bump_timer = 0.55
			_best_distance_m = _distance_m
			save_best_distance()
			var gs = get_node_or_null("/root/GameState")
			if gs:
				gs.best_distance = _best_distance_m

	if _coin_pop_timer > 0.0: _coin_pop_timer -= delta
	if _gem_pop_timer > 0.0: _gem_pop_timer -= delta
	if _dist_bump_timer > 0.0: _dist_bump_timer -= delta
	if _coin_digit_flash > 0.0: _coin_digit_flash -= delta
	if _streak_timer > 0.0: _streak_timer -= delta
	else: _streak_shown = false
	if _petrol_fill_timer > 0.0: _petrol_fill_timer -= delta

	queue_redraw()

func add_coin(amount: int = 1) -> void:
	coins += amount
	_last_coin_amount = amount
	_coin_pop_timer = 0.60
	_coin_digit_flash = 0.60
	
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.add_to_total_coins(amount)

func add_gem(amount: int = 1) -> void:
	gems += amount
	_last_gem_amount = amount
	_gem_pop_timer = 0.60
	
	var gs = get_node_or_null("/root/GameState")
	if gs:
		gs.add_to_total_gems(amount)



func fill_petrol(amount: float = 30.0) -> void:
	var old = petrol
	petrol = clamp(petrol + amount, 0.0, petrol_max)
	_petrol_fill_amount = petrol - old
	_petrol_fill_timer = 0.80

func _draw() -> void:
	# Use custom font if loaded, otherwise fall back dynamically
	var font = custom_font if custom_font else get_theme_default_font()

	# ── Timers ────────────────────────────────────────────────────────
	var coin_t = clamp(_coin_pop_timer / 0.60, 0.0, 1.0)
	var dist_t = clamp(_dist_bump_timer / 0.55, 0.0, 1.0)
	var flash_t = clamp(_coin_digit_flash / 0.60, 0.0, 1.0)
	var streak_t = clamp(_streak_timer / 1.20, 0.0, 1.0)

	# ── Typography Scale & Bob Animations (Numbers size slightly down) ──
	var coin_scale = 1.0 + sin(_elapsed * 4.0) * 0.015
	var coin_size = int(48.0 * coin_scale) # Sized down from 65.0

	var dist_pop = sin(dist_t * PI) * 0.28
	var dist_scale = 1.0 + dist_pop + sin(_elapsed * 3.0) * 0.01
	var dist_size = int(48.0 * dist_scale) # Sized down from 65.0
	var dist_y_offset = -dist_pop * 14.0

	# ── ROW 1: [coin symbol]xxxxxx | [Location symbol] yyy M ───────────
	# 1. Coin Symbol (Enlarged 1.3x more: radius 21.0)
	var coin_center = Vector2(26.0, 26.0)
	var coin_rad = 21.0
	
	# Outermost black border
	draw_circle(coin_center, coin_rad, Color.BLACK)
	
	var _color_main = Color(0.88, 0.60, 0.02)
	var _color_inner = Color(1.0, 0.88, 0.28)
	var _color_gem_dark = Color(0.72, 0.44, 0.0)
	var _color_gem_light = Color(1.0, 0.95, 0.6)
	
	# 1. Outer Base Coin Body
	draw_circle(coin_center, coin_rad - 1.5, _color_main)

	# 2. Inner Face
	draw_circle(coin_center, coin_rad - 5.0, _color_inner)

	# 3. Inner decorative concentric groove ring
	draw_arc(coin_center, coin_rad - 8.0, 0.0, TAU, 36, _color_main.lerp(Color.BLACK, 0.1), 1.5)

	# 4. Smooth specular gloss highlight (top-left crescent)
	draw_circle(coin_center - Vector2(coin_rad * 0.25, coin_rad * 0.25), coin_rad * 0.4, Color(1.0, 1.0, 1.0, 0.4))

	# 5. High-contrast crisp outer rim border
	draw_arc(coin_center, coin_rad - 2.0, 0.0, TAU, 40, _color_main.lerp(Color.BLACK, 0.4), 2.5)

	# 6. Premium Geometric Inside Design: Layered Diamond Core
	var d_size = coin_rad * 0.40
	var d_shadow = Color(0.0, 0.0, 0.0, 0.35)
	
	var d_top = coin_center + Vector2(0, -d_size)
	var d_bottom = coin_center + Vector2(0, d_size)
	var d_left = coin_center + Vector2(-d_size, 0)
	var d_right = coin_center + Vector2(d_size, 0)
	
	# Diamond Shadow Offset
	var s_off = Vector2(0, 1.5)
	draw_colored_polygon(PackedVector2Array([d_top + s_off, d_right + s_off, d_bottom + s_off, d_left + s_off]), d_shadow)
	
	# Diamond Left Facet (Darker shade)
	draw_colored_polygon(PackedVector2Array([d_top, coin_center, d_bottom, d_left]), _color_gem_dark)
	
	# Diamond Right Facet (Lighter shade)
	draw_colored_polygon(PackedVector2Array([d_top, d_right, d_bottom, coin_center]), _color_gem_light)
	
	# Diamond Center Dividing/Border Lines
	var border_color = _color_main.lerp(Color.BLACK, 0.5)
	draw_line(d_top, d_bottom, border_color, 1.5)
	draw_line(d_left, d_right, border_color, 1.5)
	draw_polyline(PackedVector2Array([d_top, d_right, d_bottom, d_left, d_top]), border_color, 2.0)

	# 2. Coin Text (Aligned to X = 58.0 due to bigger icon)
	var color_coin_text = Color("#ffea79")
	if flash_t > 0.0:
		color_coin_text = Color(1.0, 1.0, 1.0).lerp(Color("#ffb900"), 1.0 - flash_t)
	
	var coins_val_str = str(coins)
	var coins_val_w = font.get_string_size(coins_val_str, HORIZONTAL_ALIGNMENT_LEFT, -1, coin_size).x
	_draw_clean_text(font, coins_val_str, Vector2(58.0, 50.0), coin_size, color_coin_text)

	# 3. Divider Line |
	var divider_x = 58.0 + coins_val_w + 24.0
	draw_line(Vector2(divider_x, 10.0), Vector2(divider_x, 48.0), Color(0.2, 0.25, 0.35, 0.6), 2.0)

	# 4. Location Pin Symbol (Enlarged 1.3x more: circle radius 13.0)
	var pin_center = Vector2(divider_x + 36.0, 20.0 + dist_y_offset)
	# Red neon pin
	draw_circle(pin_center, 13.0, Color("#ff2a6d"))
	var tri_pts = PackedVector2Array([
		pin_center + Vector2(-13.0, 4.0),
		pin_center + Vector2(13.0, 4.0),
		pin_center + Vector2(0.0, 25.0)
	])
	draw_colored_polygon(tri_pts, Color("#ff2a6d"))
	draw_circle(pin_center, 5.0, Color("#ffffff"))

	# 5. Distance Text (Aligned to X = divider_x + 62.0 due to bigger icon)
	var color_dist_text = Color("#ffffff")
	if dist_t > 0.0:
		color_dist_text = Color(1.0, 1.0, 1.0).lerp(Color("#05ffa1"), 1.0 - dist_t)

	var dist_val_str = "%d M" % int(_distance_m)
	var dist_val_w = font.get_string_size(dist_val_str, HORIZONTAL_ALIGNMENT_LEFT, -1, dist_size).x
	var dist_x = divider_x + 62.0
	var dist_y = 50.0 + dist_y_offset
	_draw_clean_text(font, dist_val_str, Vector2(dist_x, dist_y), dist_size, color_dist_text)

	# 6. Small High Score next to Distance
	if _best_distance_m > 0.0:
		var best_lbl_size = 20
		var best_str = "/  BEST %d M" % int(_best_distance_m)
		_draw_clean_label(font, best_str, Vector2(dist_x + dist_val_w + 24, dist_y), best_lbl_size, Color("#ffffff", 0.45))

	# ── ROW 2: [Petrol Symbol]######## ────────────────────────────────
	# 1. Avatar Box [   ] containing Petrol Jerrycan Symbol
	var av_rect = Rect2(0, 68, 58, 58)
	var av_pos = av_rect.position
	
	# Draw background box outline with bold comic style (black borders + offset black shadow)
	var av_shadow = StyleBoxFlat.new()
	av_shadow.bg_color = Color.BLACK
	av_shadow.set_corner_radius_all(10)
	draw_style_box(av_shadow, Rect2(av_rect.position + Vector2(4, 4), av_rect.size))
	
	var av_sb = StyleBoxFlat.new()
	av_sb.bg_color = Color("#1e1e24")
	av_sb.border_color = Color.BLACK
	av_sb.set_border_width_all(3)
	av_sb.set_corner_radius_all(10)
	draw_style_box(av_sb, av_rect)

	# Low fuel alarm calculation
	var ratio: float = clamp(petrol / petrol_max, 0.0, 1.0)
	var is_low: bool = ratio < 0.25

	# Draw Classic Jerrycan Petrol Symbol (Filled shapes, no outline)
	var fuel_orange = Color("#ff9900")
	if is_low and sin(_elapsed * 12.0) > 0.0:
		fuel_orange = Color("#ff2a2a") # Blink red on low fuel
	
	var can_pos = av_pos + Vector2(17, 15)
	var dark_bg = Color(0.08, 0.08, 0.12)

	# Main body (solid filled)
	draw_rect(Rect2(can_pos.x, can_pos.y, 24, 28), fuel_orange, true)
	
	# Spout (solid filled, slanted top-left)
	var spout_pts = PackedVector2Array([
		can_pos + Vector2(2, 0),
		can_pos + Vector2(4, -4),
		can_pos + Vector2(1, -5),
		can_pos + Vector2(-1, -1)
	])
	draw_colored_polygon(spout_pts, fuel_orange)

	# Handle (solid filled, top-right)
	draw_rect(Rect2(can_pos.x + 8, can_pos.y - 4, 14, 4), fuel_orange, true)
	# Cutout gap inside handle (matching shadow background)
	draw_rect(Rect2(can_pos.x + 11, can_pos.y - 2, 8, 2), dark_bg, true)

	# Debossed X pattern (drawn using thick lines matching background)
	draw_line(can_pos + Vector2(6, 7), can_pos + Vector2(18, 21), dark_bg, 3.0)
	draw_line(can_pos + Vector2(18, 7), can_pos + Vector2(6, 21), dark_bg, 3.0)

	# 2. Slanted Retro Petrol Bar (1.2x Enlarged, next to petrol icon)
	_draw_slanted_petrol_bar(77, 74)

	# +N Popups (Rising cleanly above the coin counter)
	if _coin_pop_timer > 0.0:
		var fade = coin_t
		var rise = (1.0 - fade) * 43.0
		var popup_x = 58.0 + (coins_val_w / 2.0)
		_draw_clean_text(font, "+%d" % _last_coin_amount, Vector2(popup_x - 12, -8.0 - rise), 30, Color("#ffea79", fade))
		_draw_vector_sparkles(Vector2(popup_x - 8.0, -18.0 - rise), coin_t)

	if _gem_pop_timer > 0.0:
		var gem_t = clamp(_gem_pop_timer / 0.60, 0.0, 1.0)
		var fade = gem_t
		var rise = (1.0 - fade) * 43.0
		var popup_x = 58.0 + coins_val_w + 35.0
		_draw_clean_text(font, "+%d Gem" % _last_gem_amount, Vector2(popup_x, -8.0 - rise), 30, Color("#2e86c1", fade))
		_draw_vector_sparkles(Vector2(popup_x + 30.0, -18.0 - rise), gem_t)

	# High score beaten announcement popup (Rising above the distance value)
	if _streak_shown and _streak_timer > 0.0:
		var fade = streak_t
		var rise = (1.0 - streak_t) * 20.0
		var milestone_x = dist_x + (dist_val_w / 2.0)
		_draw_clean_text(font, "NEW BEST!", Vector2(milestone_x - 36, -8.0 - rise), 26, Color("#ffffff", fade))

	# ── DELIVERY/RACING TARGET HUD INDICATOR (RIGHT SIDE) ─────────────
	var road = get_node_or_null("/root/main/Road")
	if road:
		if road.get("delivery_target_chunk") != -1:
			var target_chunk = road.get("delivery_target_chunk")
			var target_x = (target_chunk + 0.5) * road.get("chunk_width")
			if road.get("active_chunks").has(target_chunk):
				var chunk_data = road.get("active_chunks")[target_chunk]
				if "house" in chunk_data and is_instance_valid(chunk_data.house):
					target_x = chunk_data.house.global_position.x
					
			var dist_rem = 0.0
			if is_instance_valid(chassis):
				dist_rem = (target_x - chassis.global_position.x) / 30.0
				
			if dist_rem > -50.0:
				var crates_needed = road.get("delivery_crate_count")
				var crates_delivered = road.get("delivery_crates_delivered")
				
				var screen_w = get_viewport_rect().size.x
				var indicator_w = 220.0
				var opponent = road.get("active_opponent")
				var has_opponent = is_instance_valid(opponent)
				var indicator_h = 135.0 if has_opponent else 105.0
				var right_margin = 38.0
				
				var ibox_x = screen_w - global_position.x - indicator_w - right_margin
				var ibox_y = 68.0 # Align vertically with Petrol bar box
				
				var ibox = Rect2(ibox_x, ibox_y, indicator_w, indicator_h)
				
				var pulse = 0.5 + 0.5 * sin(_elapsed * 6.0)
				var green_glow = Color("#00ff66", 0.12 + 0.08 * pulse)
				var green_line = Color("#00ff66", 0.8 + 0.2 * pulse)
				
				# 1. Hard Offset Comic Shadow Box
				var shadow_sb = StyleBoxFlat.new()
				shadow_sb.bg_color = Color.BLACK
				shadow_sb.set_corner_radius_all(12)
				draw_style_box(shadow_sb, Rect2(ibox.position + Vector2(6, 6), ibox.size))
				
				# 2. Foreground Comic Panel (Solid dark slate background + thick black borders)
				var sb = StyleBoxFlat.new()
				sb.bg_color = Color("#1e1e24")
				sb.border_color = Color.BLACK
				sb.set_border_width_all(3)
				sb.set_corner_radius_all(12)
				draw_style_box(sb, ibox)
				
				# 3. Solid Header Accent Strip (Solid Green `#00ff66` with thick black bottom border)
				var header_rect = Rect2(ibox.position.x + 3, ibox.position.y + 3, ibox.size.x - 6, 28)
				var header_sb = StyleBoxFlat.new()
				header_sb.bg_color = Color("#00ff66")
				header_sb.border_color = Color.BLACK
				header_sb.border_width_bottom = 3
				header_sb.corner_radius_top_left = 9
				header_sb.corner_radius_top_right = 9
				draw_style_box(header_sb, header_rect)
				
				var lbl_font_size = 14
				var val_font_size = 18
				
				if has_opponent:
					# Line 1: Title (drawn in solid black inside the green header)
					var title_str = "DELIVERY TARGET"
					_draw_comic_header_text(font, title_str, Vector2(ibox_x + indicator_w / 2.0, ibox_y + 14.0), lbl_font_size)
					
					# Line 2: Crates Count
					var progress_str = "CRATES: %d/%d" % [crates_delivered, crates_needed]
					_draw_comic_body_text_center(font, progress_str, Vector2(ibox_x + indicator_w / 2.0, ibox_y + 54.0), val_font_size, Color("#ffffff"))
					
					# Line 3: Position
					var pos_str = "POSITION: 1st"
					if is_instance_valid(chassis) and is_instance_valid(opponent):
						if chassis.global_position.x < opponent.global_position.x:
							pos_str = "POSITION: 2nd"
					_draw_comic_body_text_center(font, pos_str, Vector2(ibox_x + indicator_w / 2.0, ibox_y + 80.0), val_font_size, Color("#ffea79"))
					
					# Line 4: Distance remaining & flash arrow
					var dist_str = "%d M" % int(max(0.0, dist_rem))
					if dist_rem <= 0.0:
						dist_str = "ARRIVED"
						
					var arrow_char = "▶"
					if dist_rem < 0.0:
						arrow_char = "◀"
						
					var dist_text = "%s  %s  %s" % [arrow_char, dist_str, arrow_char]
					
					# Breathing pulse that speeds up as you approach target
					var pulse_speed = 14.0 if dist_rem < 150.0 else 6.0
					var dist_color = Color("#00ff66").lerp(Color(1.0, 1.0, 1.0, 0.9), 0.35 + 0.35 * sin(_elapsed * pulse_speed))
					_draw_comic_body_text_center(font, dist_text, Vector2(ibox_x + indicator_w / 2.0, ibox_y + 112.0), val_font_size, dist_color)
				else:
					# Line 1: Title
					var title_str = "DELIVERY TARGET"
					_draw_comic_header_text(font, title_str, Vector2(ibox_x + indicator_w / 2.0, ibox_y + 14.0), lbl_font_size)
					
					# Line 2: Crates Count
					var progress_str = "CRATES: %d/%d" % [crates_delivered, crates_needed]
					_draw_comic_body_text_center(font, progress_str, Vector2(ibox_x + indicator_w / 2.0, ibox_y + 56.0), val_font_size, Color("#ffffff"))
					
					# Line 3: Distance remaining & flash arrow
					var dist_str = "%d M" % int(max(0.0, dist_rem))
					if dist_rem <= 0.0:
						dist_str = "ARRIVED"
						
					var arrow_char = "▶"
					if dist_rem < 0.0:
						arrow_char = "◀"
						
					var dist_text = "%s  %s  %s" % [arrow_char, dist_str, arrow_char]
					
					var pulse_speed = 14.0 if dist_rem < 150.0 else 6.0
					var dist_color = Color("#00ff66").lerp(Color(1.0, 1.0, 1.0, 0.9), 0.35 + 0.35 * sin(_elapsed * pulse_speed))
					_draw_comic_body_text_center(font, dist_text, Vector2(ibox_x + indicator_w / 2.0, ibox_y + 88.0), val_font_size, dist_color)
		
		elif road.get("racing_target_chunk") != -1:
			var target_chunk = road.get("racing_target_chunk")
			var target_x = (target_chunk + 0.5) * road.get("chunk_width")
			if road.get("active_chunks").has(target_chunk):
				var chunk_data = road.get("active_chunks")[target_chunk]
				if "house" in chunk_data and is_instance_valid(chunk_data.house):
					target_x = chunk_data.house.global_position.x
					
			var dist_rem = 0.0
			if is_instance_valid(chassis):
				dist_rem = (target_x - chassis.global_position.x) / 30.0
				
			if dist_rem > -50.0:
				var screen_w = get_viewport_rect().size.x
				var indicator_w = 220.0
				var opponent = road.get("active_opponent")
				var has_opponent = is_instance_valid(opponent)
				var indicator_h = 135.0 if has_opponent else 105.0
				var right_margin = 38.0
				
				var ibox_x = screen_w - global_position.x - indicator_w - right_margin
				var ibox_y = 68.0 # Align vertically with Petrol bar box
				
				var ibox = Rect2(ibox_x, ibox_y, indicator_w, indicator_h)
				
				var pulse = 0.5 + 0.5 * sin(_elapsed * 6.0)
				var pink_glow = Color("#ff007f", 0.12 + 0.08 * pulse)
				var pink_line = Color("#ff007f", 0.8 + 0.2 * pulse)
				
				# 1. Hard Offset Comic Shadow Box
				var shadow_sb = StyleBoxFlat.new()
				shadow_sb.bg_color = Color.BLACK
				shadow_sb.set_corner_radius_all(12)
				draw_style_box(shadow_sb, Rect2(ibox.position + Vector2(6, 6), ibox.size))
				
				# 2. Foreground Comic Panel (Solid dark slate background + thick black borders)
				var sb = StyleBoxFlat.new()
				sb.bg_color = Color("#1e1e24")
				sb.border_color = Color.BLACK
				sb.set_border_width_all(3)
				sb.set_corner_radius_all(12)
				draw_style_box(sb, ibox)
				
				# 3. Solid Header Accent Strip (Solid Pink `#ff007f` with thick black bottom border)
				var header_rect = Rect2(ibox.position.x + 3, ibox.position.y + 3, ibox.size.x - 6, 28)
				var header_sb = StyleBoxFlat.new()
				header_sb.bg_color = Color("#ff007f")
				header_sb.border_color = Color.BLACK
				header_sb.border_width_bottom = 3
				header_sb.corner_radius_top_left = 9
				header_sb.corner_radius_top_right = 9
				draw_style_box(header_sb, header_rect)
				
				var lbl_font_size = 14
				var val_font_size = 18
				
				if has_opponent:
					# Line 1: Title
					var title_str = "RACING TARGET"
					_draw_comic_header_text(font, title_str, Vector2(ibox_x + indicator_w / 2.0, ibox_y + 14.0), lbl_font_size)
					
					# Line 2: Race details
					var progress_str = "FINISH LINE"
					_draw_comic_body_text_center(font, progress_str, Vector2(ibox_x + indicator_w / 2.0, ibox_y + 54.0), val_font_size, Color("#ffffff"))
					
					# Line 3: Position
					var pos_str = "POSITION: 1st"
					if is_instance_valid(chassis) and is_instance_valid(opponent):
						if chassis.global_position.x < opponent.global_position.x:
							pos_str = "POSITION: 2nd"
					_draw_comic_body_text_center(font, pos_str, Vector2(ibox_x + indicator_w / 2.0, ibox_y + 80.0), val_font_size, Color("#ffea79"))
					
					# Line 4: Distance remaining & flash arrow
					var dist_str = "%d M" % int(max(0.0, dist_rem))
					if dist_rem <= 0.0:
						dist_str = "ARRIVED"
						
					var arrow_char = "▶"
					if dist_rem < 0.0:
						arrow_char = "◀"
						
					var dist_text = "%s  %s  %s" % [arrow_char, dist_str, arrow_char]
					
					var pulse_speed = 14.0 if dist_rem < 150.0 else 6.0
					var dist_color = Color("#ff007f").lerp(Color(1.0, 1.0, 1.0, 0.9), 0.35 + 0.35 * sin(_elapsed * pulse_speed))
					_draw_comic_body_text_center(font, dist_text, Vector2(ibox_x + indicator_w / 2.0, ibox_y + 112.0), val_font_size, dist_color)
				else:
					# Line 1: Title
					var title_str = "RACING TARGET"
					_draw_comic_header_text(font, title_str, Vector2(ibox_x + indicator_w / 2.0, ibox_y + 14.0), lbl_font_size)
					
					# Line 2: Race details
					var progress_str = "FINISH LINE"
					_draw_comic_body_text_center(font, progress_str, Vector2(ibox_x + indicator_w / 2.0, ibox_y + 56.0), val_font_size, Color("#ffffff"))
					
					# Line 3: Distance remaining & flash arrow
					var dist_str = "%d M" % int(max(0.0, dist_rem))
					if dist_rem <= 0.0:
						dist_str = "ARRIVED"
						
					var arrow_char = "▶"
					if dist_rem < 0.0:
						arrow_char = "◀"
						
					var dist_text = "%s  %s  %s" % [arrow_char, dist_str, arrow_char]
					
					var pulse_speed = 14.0 if dist_rem < 150.0 else 6.0
					var dist_color = Color("#ff007f").lerp(Color(1.0, 1.0, 1.0, 0.9), 0.35 + 0.35 * sin(_elapsed * pulse_speed))
					_draw_comic_body_text_center(font, dist_text, Vector2(ibox_x + indicator_w / 2.0, ibox_y + 88.0), val_font_size, dist_color)
		
		elif road.get("towing_target_chunk") != -1:
			var target_chunk = road.get("towing_target_chunk")
			var target_x = (target_chunk + 0.5) * road.get("chunk_width")
			if road.get("active_chunks").has(target_chunk):
				var chunk_data = road.get("active_chunks")[target_chunk]
				if "house" in chunk_data and is_instance_valid(chunk_data.house):
					target_x = chunk_data.house.global_position.x
					
			var dist_rem = 0.0
			if is_instance_valid(chassis):
				dist_rem = (target_x - chassis.global_position.x) / 30.0
				
			if dist_rem > -50.0:
				var screen_w = get_viewport_rect().size.x
				var indicator_w = 220.0
				var indicator_h = 105.0
				var right_margin = 38.0
				
				var ibox_x = screen_w - global_position.x - indicator_w - right_margin
				var ibox_y = 68.0 # Align vertically with Petrol bar box
				
				var ibox = Rect2(ibox_x, ibox_y, indicator_w, indicator_h)
				
				var pulse = 0.5 + 0.5 * sin(_elapsed * 6.0)
				var amber_glow = Color("#ff9f00", 0.12 + 0.08 * pulse)
				var amber_line = Color("#ff9f00", 0.8 + 0.2 * pulse)
				
				# 1. Hard Offset Comic Shadow Box
				var shadow_sb = StyleBoxFlat.new()
				shadow_sb.bg_color = Color.BLACK
				shadow_sb.set_corner_radius_all(12)
				draw_style_box(shadow_sb, Rect2(ibox.position + Vector2(6, 6), ibox.size))
				
				# 2. Foreground Comic Panel (Solid dark slate background + thick black borders)
				var sb = StyleBoxFlat.new()
				sb.bg_color = Color("#1e1e24")
				sb.border_color = Color.BLACK
				sb.set_border_width_all(3)
				sb.set_corner_radius_all(12)
				draw_style_box(sb, ibox)
				
				# 3. Solid Header Accent Strip (Solid Amber `#ff9f00` with thick black bottom border)
				var header_rect = Rect2(ibox.position.x + 3, ibox.position.y + 3, ibox.size.x - 6, 28)
				var header_sb = StyleBoxFlat.new()
				header_sb.bg_color = Color("#ff9f00")
				header_sb.border_color = Color.BLACK
				header_sb.border_width_bottom = 3
				header_sb.corner_radius_top_left = 9
				header_sb.corner_radius_top_right = 9
				draw_style_box(header_sb, header_rect)
				
				var lbl_font_size = 14
				var val_font_size = 18
				
				# Line 1: Title
				var title_str = "TOWING TARGET"
				_draw_comic_header_text(font, title_str, Vector2(ibox_x + indicator_w / 2.0, ibox_y + 14.0), lbl_font_size)
				
				# Line 2: Tow details
				var progress_str = "TOW VEHICLE"
				_draw_comic_body_text_center(font, progress_str, Vector2(ibox_x + indicator_w / 2.0, ibox_y + 54.0), val_font_size, Color("#ffffff"))
				
				# Line 3: Distance remaining & flash arrow
				var dist_str = "%d M" % int(max(0.0, dist_rem))
				if dist_rem <= 0.0:
					dist_str = "ARRIVED"
					
				var arrow_char = "▶"
				if dist_rem < 0.0:
					arrow_char = "◀"
					
				var dist_text = "%s  %s  %s" % [arrow_char, dist_str, arrow_char]
				
				var pulse_speed = 14.0 if dist_rem < 150.0 else 6.0
				var dist_color = Color("#ff9f00").lerp(Color(1.0, 1.0, 1.0, 0.9), 0.35 + 0.35 * sin(_elapsed * pulse_speed))
				_draw_comic_body_text_center(font, dist_text, Vector2(ibox_x + indicator_w / 2.0, ibox_y + 86.0), val_font_size, dist_color)

# ── Drawing Engines ──────────────────────────────────────────────────────

func _draw_slanted_petrol_bar(start_x: float, bar_y: float) -> void:
	var cell_w := 22.0        # 18 * 1.2
	var cell_h := 46.0        # 38 * 1.2
	var cell_gap := 6.0       # 5 * 1.2
	var slant := -6.0         # -5 * 1.2
	var outline_width := 2.4   # 2 * 1.2
	var outline_color := Color(0.08, 0.08, 0.12)

	var ratio: float = clamp(petrol / petrol_max, 0.0, 1.0)
	var active_cells_count = int(ceil(ratio * 10.0))
	var is_low: bool = ratio < 0.25

	# Setup spring scale popup animation when refilled
	var fill_t = clamp(_petrol_fill_timer / 0.80, 0.0, 1.0)
	var cell_scale = 1.0
	if fill_t > 0.0:
		cell_scale = 1.0 + sin(fill_t * PI) * 0.22

	for i in range(10):
		# Wave bobbing when low fuel (equalizer look)
		var bob = 0.0
		if is_low:
			bob = sin(_elapsed * 12.0 + i * 0.8) * 3.5

		# Center coords for scaling
		var cx = start_x + i * (cell_w + cell_gap) + cell_w / 2.0
		var cy = bar_y + cell_h / 2.0
		
		var curr_w = cell_w * cell_scale
		var curr_h = cell_h * cell_scale
		var cell_rect = Rect2(cx - curr_w / 2.0, cy - curr_h / 2.0, curr_w, curr_h)

		var cell_color = Color("#00e676") # Green healthy
		if i < 3:
			cell_color = Color("#ff3d00") # Red danger
		elif i < 7:
			cell_color = Color("#ffb900") # Yellow warning

		# Flash low fuel active cells
		if is_low and i < active_cells_count:
			var pulse = 0.4 + (0.6 * (0.5 + sin(_elapsed * 15.0) * 0.5))
			cell_color.a = pulse

		if i < active_cells_count:
			draw_slanted_bar_cell(cell_rect, cell_color, outline_color, outline_width, slant, bob)
		else:
			# Inactive slots
			var bg_c = Color(0.18, 0.2, 0.25, 0.45)
			draw_slanted_bar_cell(cell_rect, bg_c, outline_color, outline_width, slant, bob)

	# Fuel Refuel "+X" text above the bar
	if _petrol_fill_timer > 0.0:
		var font = custom_font if custom_font else get_theme_default_font()
		var ft = clamp(_petrol_fill_timer / 0.80, 0.0, 1.0)
		var rise = (1.0 - ft) * 24.0
		var popup_str = "+%dL" % int(_petrol_fill_amount)
		var text_x = start_x + (10.0 * (cell_w + cell_gap)) + 14.0
		_draw_clean_text(font, popup_str, Vector2(text_x, bar_y + 28.0 - rise), 24, Color("#00e676", ft))

func draw_slanted_bar_cell(rect: Rect2, color: Color, outline_color: Color, outline_width: float, slant: float, bob: float) -> void:
	var tl = Vector2(rect.position.x + slant, rect.position.y + bob)
	var tr = Vector2(rect.position.x + rect.size.x + slant, rect.position.y + bob)
	var br = Vector2(rect.position.x + rect.size.x, rect.position.y + rect.size.y + bob)
	var bl = Vector2(rect.position.x, rect.position.y + rect.size.y + bob)
	
	# Skewed filled polygon
	var points = PackedVector2Array([tl, tr, br, bl])
	draw_colored_polygon(points, color)
	
	# Skewed border line
	var outline_points = PackedVector2Array([tl, tr, br, bl, tl])
	draw_polyline(outline_points, outline_color, outline_width)

func _draw_clean_text(font: Font, text: String, pos: Vector2, font_size: int, color: Color) -> void:
	# Outer dark 3D offset shadow
	draw_string(font, pos + Vector2(2.5, 2.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.04, 0.04, 0.08, 0.85))
	
	# Subtle neon backlight glow offset
	var neon_glow = Color(0.0, 0.94, 1.0, 0.35)
	if color.r > 0.8 and color.g < 0.3:
		neon_glow = Color(1.0, 0.16, 0.43, 0.35) # Neon pink glow
	elif color.r > 0.8 and color.g > 0.8:
		neon_glow = Color(1.0, 0.85, 0.0, 0.3) # Gold glow
	draw_string(font, pos + Vector2(-1.0, -1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, neon_glow)
	
	# Main foreground text
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_clean_label(font: Font, text: String, pos: Vector2, font_size: int, color: Color) -> void:
	draw_string(font, pos + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.6))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_vector_sparkles(origin: Vector2, coin_t: float) -> void:
	var fade = coin_t
	var count = 4
	for i in range(count):
		var angle = (_elapsed * 4.5) + (float(i) * (TAU / count))
		var distance = (1.0 - fade) * 35.0
		var spark_pos = origin + Vector2(cos(angle), sin(angle)) * distance
		var star_size = 4.5 * fade
		var c = Color("#ffea79", fade * 0.75) if i % 2 == 0 else Color("#00f0ff", fade * 0.75)
		
		draw_line(spark_pos - Vector2(star_size, 0), spark_pos + Vector2(star_size, 0), c, 1.2)
		draw_line(spark_pos - Vector2(0, star_size), spark_pos + Vector2(0, star_size), c, 1.2)

func _draw_clean_text_center(font: Font, text: String, center_pos: Vector2, font_size: int, color: Color) -> void:
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos = center_pos - Vector2(text_size.x / 2.0, -font_size / 2.0)
	
	# Shadow
	draw_string(font, pos + Vector2(2.0, 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.04, 0.04, 0.08, 0.85))
	
	# Neon glow backlight
	var neon_glow = Color(0.0, 0.94, 1.0, 0.35)
	if color.r > 0.8 and color.g < 0.3:
		neon_glow = Color(1.0, 0.16, 0.43, 0.35) # Neon pink
	elif color.g > 0.8 and color.r < 0.3:
		neon_glow = Color(0.0, 1.0, 0.4, 0.35) # Neon green
	elif color.r > 0.8 and color.g > 0.8:
		neon_glow = Color(1.0, 0.85, 0.0, 0.3) # Gold glow
	draw_string(font, pos + Vector2(-1.0, -1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, neon_glow)
	
	# Foreground text
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_comic_header_text(font: Font, text: String, center_pos: Vector2, font_size: int) -> void:
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos = center_pos - Vector2(text_size.x / 2.0, -font_size / 2.0)
	# Solid black bold text, offset by 1.5px shadow
	draw_string(font, pos + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.35))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)

func _draw_comic_body_text_center(font: Font, text: String, center_pos: Vector2, font_size: int, color: Color) -> void:
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos = center_pos - Vector2(text_size.x / 2.0, -font_size / 2.0)
	# Solid thick black outline shadow (offset 2px in 4 directions)
	for offset in [Vector2(2, 2), Vector2(-1.5, 1.5), Vector2(1.5, -1.5), Vector2(-1.5, -1.5)]:
		draw_string(font, pos + offset, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	# Foreground text
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)