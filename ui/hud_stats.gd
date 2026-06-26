extends Control

# Custom Font Configuration
const FONT_PATH: String = "res://retro_font.ttf" # Change this to your exact font file path
var custom_font: Font

# Public State
var coins: int = 0
var _coin_pop_timer: float = 0.0
var _coin_pop_scale: float = 1.0

# Petrol State
var petrol: float = 100.0        # 0–100
var petrol_max: float = 100.0
var _petrol_fill_timer: float = 0.0  # animation when refilled
var _petrol_fill_amount: float = 0.0

# Internal
var chassis: RigidBody2D
var _start_x: float = 0.0
var _distance_m: float = 0.0
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

	# ── Responsive Safe-Zone Setup ────────────────────────────────────
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.5
	anchor_bottom = 0.4
	
	offset_left = 32.0
	offset_top = 32.0
	offset_right = 0.0
	offset_bottom = 0.0

func _process(delta: float) -> void:
	_elapsed += delta

	if is_instance_valid(chassis):
		var raw = (chassis.global_position.x - _start_x) / 30.0
		_distance_m = max(_distance_m, raw)
		if _distance_m > _best_distance_m:
			_best_distance_m = _distance_m

	var milestone = int(_distance_m / 100)
	if milestone > _last_milestone:
		_last_milestone = milestone
		_dist_bump_timer = 0.55
		_streak_timer = 1.2
		_streak_shown = true

	if _coin_pop_timer > 0.0: _coin_pop_timer -= delta
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

	# ── Typography Scale ──────────────────────────────────────────────
	var coin_pop = sin(coin_t * PI) * 0.30
	var coin_scale = 1.0 + coin_pop + sin(_elapsed * 4.0) * 0.02
	var coin_size = int(58.0 * coin_scale)

	var dist_pop = sin(dist_t * PI) * 0.20
	var dist_scale = 1.0 + dist_pop + sin(_elapsed * 2.5) * 0.01
	var dist_size = int(48.0 * dist_scale)

	# ── Clean Spaced Layout Stack ─────────────────────────────────────
	var score_lbl_y = 24.0
	var score_val_y = score_lbl_y + 54.0
	
	var dist_lbl_y = score_val_y + 44.0
	var dist_val_y = dist_lbl_y + 46.0
	
	var hi_score_y = dist_val_y + 38.0

	var petrol_lbl_y = hi_score_y + 36.0
	var petrol_bar_y = petrol_lbl_y + 18.0

	# ── Premium Arcade Color Palette ──────────────────────────────────
	# Neon Coral/Crimson for headers
	var color_score_lbl = Color("#ff2a6d")
	if _coin_pop_timer > 0.0 and sin(_elapsed * 35.0) > 0.0:
		color_score_lbl = Color(1.0, 1.0, 1.0, 0.4) # Aesthetic hit-flicker

	# Rich, warm 18K Arcade Gold for numbers		
	var color_coin_text = Color("#05ff00")
	if flash_t > 0.0:
		color_coin_text = Color(1.0, 1.0, 1.0).lerp(Color("#ffb900"), 1.0 - flash_t)

	# Vivid Electric Cyan/Mint suite
	var color_dist_lbl = Color("#00f0ff")
	var color_dist_text = Color("#9b20ffff") if dist_t <= 0.0 else Color(0.80, 1.0, 0.95).lerp(Color("#05ffa1"), 1.0 - dist_t)

	# ── Draw Elements ─────────────────────────────────────────────────
	# SCORE BLOCK
	_draw_clean_label(font, "COINS", Vector2(0, score_lbl_y), 14, color_score_lbl)
	var coin_str = str(coins)
	_draw_clean_text(font, coin_str, Vector2(0, score_val_y), coin_size, color_coin_text)

	# DISTANCE BLOCK
	_draw_clean_label(font, "DISTANCE", Vector2(0, dist_lbl_y), 14, color_dist_lbl)
	var dist_str = "%d M" % int(_distance_m)
	_draw_clean_text(font, dist_str, Vector2(0, dist_val_y), dist_size, color_dist_text)

	# HI-SCORE BLOCK (Minimalist white ivory with soft alpha)
	if _best_distance_m > 0.0:
		var best_str = "HI-SCORE  %d M" % int(_best_distance_m)
		_draw_clean_label(font, best_str, Vector2(0, hi_score_y), 13, Color("#f0f4f8", 0.35))

	# ── PETROL BAR ────────────────────────────────────────────────────
	_draw_petrol_bar(font, petrol_lbl_y, petrol_bar_y)

	# ── FX Overlays ───────────────────────────────────────────────────
	# +N Popups
	if _coin_pop_timer > 0.0:
		var fade = coin_t
		var rise = (1.0 - fade) * 32.0
		var popup_x = (coin_str.length() * (coin_size * 0.55)) + 24.0
		_draw_clean_text(font, "+%d" % _last_coin_amount, Vector2(popup_x, score_val_y - rise), 24, Color("#fff4a3", fade))
		_draw_vector_sparkles(Vector2(popup_x - 8.0, score_val_y - 18.0), coin_t)

	# Milestone Alerts
	if _streak_shown and _streak_timer > 0.0:
		var fade = streak_t
		var rise = (1.0 - streak_t) * 16.0
		var milestone_x = (dist_str.length() * (dist_size * 0.55)) + 28.0
		_draw_clean_text(font, "MILESTONE!", Vector2(milestone_x, dist_val_y - rise), 24, Color("#ffffff", fade))

# ── Drawing Engines ──────────────────────────────────────────────────────

func _draw_petrol_bar(font: Font, lbl_y: float, bar_y: float) -> void:
	var bar_w: float = 130.0
	var bar_h: float = 14.0
	var ratio: float = clamp(petrol / petrol_max, 0.0, 1.0)
	var is_low: bool = ratio < 0.25

	# Label — flicker red when low
	var lbl_color: Color
	if is_low and sin(_elapsed * 9.0) > 0.0:
		lbl_color = Color("#ff2a2a")
	else:
		lbl_color = Color("#ff9900")
	_draw_clean_label(font, "FUEL", Vector2(0, lbl_y), 14, lbl_color)

	# Background track
	draw_rect(Rect2(0.0, bar_y, bar_w, bar_h), Color(0.08, 0.08, 0.12, 0.75), true)
	draw_rect(Rect2(0.0, bar_y, bar_w, bar_h), Color(0.2, 0.2, 0.3, 0.5), false, 1.0)

	# Filled portion with gradient colour: green → orange → red
	var fill_w: float = bar_w * ratio
	var fill_color: Color
	if ratio > 0.5:
		fill_color = Color("#00e676").lerp(Color("#ff9900"), 1.0 - ((ratio - 0.5) * 2.0))
	elif ratio > 0.25:
		fill_color = Color("#ff9900").lerp(Color("#ff3d00"), 1.0 - ((ratio - 0.25) * 4.0))
	else:
		var low_pulse = 0.5 + sin(_elapsed * 8.0) * 0.5
		fill_color = Color("#ff3d00", 0.6 + low_pulse * 0.4)
	if fill_w > 1.0:
		draw_rect(Rect2(0.0, bar_y, fill_w, bar_h), fill_color, true)

	# Segment ticks (5 divisions)
	for i in range(1, 5):
		var tx = (bar_w / 5.0) * i
		draw_line(Vector2(tx, bar_y + 2.0), Vector2(tx, bar_y + bar_h - 2.0), Color(0.0, 0.0, 0.0, 0.3), 1.0)

	# Glow edge on top of fill
	if fill_w > 2.0:
		var glow_c = fill_color.lightened(0.35)
		glow_c.a = 0.7
		draw_line(Vector2(fill_w - 1.5, bar_y + 1.5), Vector2(fill_w - 1.5, bar_y + bar_h - 1.5), glow_c, 2.5)

	# Fill popup: "+Xℓ" rising text
	if _petrol_fill_timer > 0.0:
		var ft = clamp(_petrol_fill_timer / 0.80, 0.0, 1.0)
		var rise = (1.0 - ft) * 24.0
		var popup_str = "+%dL" % int(_petrol_fill_amount)
		_draw_clean_text(font, popup_str, Vector2(bar_w + 8.0, bar_y - rise), 20, Color("#00e676", ft))

func _draw_clean_text(font: Font, text: String, pos: Vector2, font_size: int, color: Color) -> void:
	# Ultra soft clean drop projection to enhance visibility over game backgrounds without an ugly outline
	draw_string(font, pos + Vector2(1.5, 1.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.20))
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_clean_label(font: Font, text: String, pos: Vector2, font_size: int, color: Color) -> void:
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