extends Control

# Public State
var coins: int = 0
var _coin_pop_timer: float = 0.0
var _coin_pop_scale: float = 1.0

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

	var hud = get_parent()
	var truck = hud.get_parent() if hud else null
	if truck:
		chassis = truck.get_node_or_null("chassis")

	if is_instance_valid(chassis):
		_start_x = chassis.global_position.x

	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0

	offset_left = 22.0
	offset_top = 22.0
	offset_right = 560.0
	offset_bottom = 260.0

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
		_streak_timer = 1.1
		_streak_shown = true

	if _coin_pop_timer > 0.0: _coin_pop_timer -= delta
	if _dist_bump_timer > 0.0: _dist_bump_timer -= delta
	if _coin_digit_flash > 0.0: _coin_digit_flash -= delta
	if _streak_timer > 0.0: _streak_timer -= delta
	else: _streak_shown = false

	queue_redraw()

func add_coin(amount: int = 1) -> void:
	coins += amount
	_last_coin_amount = amount
	_coin_pop_timer = 0.60
	_coin_digit_flash = 0.60

func _draw() -> void:
	var font = get_theme_default_font()

	# ── timers → normalised 0-1 progress ──────────────────────────────
	var coin_t = clamp(_coin_pop_timer / 0.60, 0.0, 1.0)
	var dist_t = clamp(_dist_bump_timer / 0.55, 0.0, 1.0)
	var flash_t = clamp(_coin_digit_flash / 0.60, 0.0, 1.0)
	var streak_t = clamp(_streak_timer / 1.10, 0.0, 1.0)

	# ── scale / size calculations ──────────────────────────────────────
	var coin_pop = sin(coin_t * PI) * 0.38
	var coin_idle = sin(_elapsed * 5.8) * 0.03
	_coin_pop_scale = 1.0 + coin_pop + coin_idle

	var dist_pop = sin(dist_t * PI) * 0.26
	var dist_idle = sin(_elapsed * 3.0) * 0.02

	var coin_size = int(72.0 * _coin_pop_scale)
	var dist_size = int(54.0 * (1.0 + dist_pop + dist_idle))

	# ── vertical positions (gentle bob) ───────────────────────────────
	var coin_y = 76.0 + sin(_elapsed * 4.2) * 1.8
	var dist_y = 162.0 + sin(_elapsed * 3.1 + 1.2) * 1.4

	# ── label strings ─────────────────────────────────────────────────
	# Retro score-style: zero-pad coins to 6 digits
	var coin_str = "%06d" % coins
	var dist_str = "%d M" % int(_distance_m)

	# Coin label prefix flickers during pop
	var label_alpha = 1.0
	if _coin_pop_timer > 0.0:
		label_alpha = 0.55 + sin(_elapsed * 28.0) * 0.45 # fast flicker

	# ── colors ────────────────────────────────────────────────────────
	# Coin: hot amber→white flash on pickup, else warm gold
	var coin_color: Color
	if flash_t > 0.0:
		coin_color = Color(1.0, 1.0, 0.6 + flash_t * 0.4).lerp(Color(1.0, 0.82, 0.12), 1.0 - flash_t)
	else:
		coin_color = Color(1.0, 0.80, 0.14)

	# Distance: cyan-mint, brighter on milestone
	var dist_color: Color
	if dist_t > 0.0:
		dist_color = Color(0.18, 1.0, 0.78).lerp(Color(0.55, 1.0, 0.88), dist_t)
	else:
		dist_color = Color(0.44, 0.98, 0.76)

	# ── draw coin row ─────────────────────────────────────────────────
	# Tiny uppercase label above
	_draw_arcade_label(font, "SCORE", Vector2(2.0, coin_y - coin_size * 0.88),
		20, Color(1.0, 0.65, 0.0, label_alpha * 0.85))

	# Score digits — each digit drawn with a slight chromatic shadow for depth
	_draw_arcade_text(font, coin_str, Vector2(0.0, coin_y),
		coin_size, coin_color, Color(1.0, 0.40, 0.0, 0.55))

	# ── sparkles on coin pickup ────────────────────────────────────────
	_draw_sparkles(Vector2(8.0, coin_y - coin_size * 0.5), coin_t)

	# ── floating +N popup ─────────────────────────────────────────────
	if _coin_pop_timer > 0.0:
		var fade = coin_t
		var rise = (1.0 - fade) * 48.0
		var wobble = sin(_elapsed * 12.0) * 4.0
		_draw_arcade_text(
			font,
			"+%d" % _last_coin_amount,
			Vector2(200.0 + wobble, coin_y - 20.0 - rise),
			32,
			Color(1.0, 0.95, 0.30, fade),
			Color(1.0, 0.55, 0.0, fade * 0.6)
		)

	# ── draw distance row ─────────────────────────────────────────────
	_draw_arcade_label(font, "DIST", Vector2(2.0, dist_y - dist_size * 0.82),
		18, Color(0.10, 0.85, 0.58, 0.80))

	_draw_arcade_text(font, dist_str, Vector2(0.0, dist_y),
		dist_size, dist_color, Color(0.0, 0.80, 0.45, 0.45))

	# ── milestone burst ───────────────────────────────────────────────
	if _streak_shown and _streak_timer > 0.0:
		var st = streak_t
		var fade = st
		var rise = (1.0 - st) * 18.0
		# "100 M!" arcade callout
		_draw_arcade_text(
			font,
			"%dM!" % (_last_milestone * 100),
			Vector2(130.0, dist_y - 36.0 - rise),
			28,
			Color(0.22, 1.0, 0.72, fade),
			Color(0.0, 0.90, 0.50, fade * 0.5)
		)

	# ── static best-distance watermark ────────────────────────────────
	if _best_distance_m > 0.0:
		var best_str = "BEST %dM" % int(_best_distance_m)
		_draw_arcade_label(font, best_str, Vector2(2.0, dist_y + 38.0),
			16, Color(0.55, 1.0, 0.80, 0.38))

# ── helpers ──────────────────────────────────────────────────────────────

func _draw_arcade_text(font: Font, text: String, pos: Vector2,
		font_size: int, color: Color, glow: Color) -> void:
	# Hard pixel shadow (offset 3,3) — classic arcade cabinet feel
	draw_string(font, pos + Vector2(3.0, 3.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Color(0.0, 0.0, 0.0, 0.70))
	# Chromatic offset — red channel shifted right gives depth without blur
	draw_string(font, pos + Vector2(2.0, 1.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Color(glow.r, 0.0, 0.0, glow.a * 0.55))
	# Glow layer
	draw_string(font, pos + Vector2(1.0, 1.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, glow)
	# Main text
	draw_string(font, pos, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_arcade_label(font: Font, text: String, pos: Vector2,
		font_size: int, color: Color) -> void:
	# Tiny uppercase category label — no glow, just a faint shadow
	draw_string(font, pos + Vector2(1.0, 1.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size,
		Color(0.0, 0.0, 0.0, 0.45))
	draw_string(font, pos, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_sparkles(origin: Vector2, coin_t: float) -> void:
	if _coin_pop_timer <= 0.0:
		return

	var fade = coin_t

	for i in range(9):
		var angle = _elapsed * 6.0 + float(i) * 0.698 # ~40° apart
		var r_base = 14.0 + float(i % 3) * 9.0
		var radius = r_base + (1.0 - fade) * 28.0
		var pos = origin + Vector2(cos(angle), sin(angle)) * radius
		var sz = 1.8 + sin(_elapsed * 14.0 + float(i) * 1.3) * 1.2

		# Alternate gold / white sparkle tips
		var sc = Color(1.0, 0.92, 0.22, fade * 0.95) if (i % 2 == 0) \
				else Color(1.0, 1.0, 0.70, fade * 0.65)

		draw_circle(pos, sz, sc)

		# Tiny cross-hair on larger sparkles for a star-burst hint
		if i % 3 == 0:
			var arm = sz * 1.6
			draw_line(pos - Vector2(arm, 0), pos + Vector2(arm, 0),
				Color(1.0, 0.95, 0.40, fade * 0.50), 1.0)
			draw_line(pos - Vector2(0, arm), pos + Vector2(0, arm),
				Color(1.0, 0.95, 0.40, fade * 0.50), 1.0)