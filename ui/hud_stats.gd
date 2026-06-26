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

func _ready() -> void:
	await get_tree().process_frame

	# Walk up: HudStats -> HUD (CanvasLayer) -> truck (Node2D)
	var hud = get_parent()
	var truck = hud.get_parent() if hud else null
	if truck:
		chassis = truck.get_node_or_null("chassis")

	if is_instance_valid(chassis):
		_start_x = chassis.global_position.x

	# Top-left HUD, text only
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 0.0
	anchor_bottom = 0.0

	offset_left = 18.0
	offset_top = 18.0
	offset_right = 330.0
	offset_bottom = 145.0

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
		_dist_bump_timer = 0.35

	if _coin_pop_timer > 0.0:
		_coin_pop_timer -= delta

	if _dist_bump_timer > 0.0:
		_dist_bump_timer -= delta

	queue_redraw()

func add_coin(amount: int = 1) -> void:
	coins += amount
	_coin_pop_timer = 0.5

func _draw() -> void:
	var font = get_theme_default_font()

	var coin_t = clamp(_coin_pop_timer / 0.5, 0.0, 1.0)
	var coin_bounce = sin(coin_t * PI) * 0.35
	var idle_pulse = sin(_elapsed * 4.5) * 0.04
	_coin_pop_scale = 1.0 + coin_bounce + idle_pulse

	var dist_t = clamp(_dist_bump_timer / 0.35, 0.0, 1.0)
	var dist_scale = 1.0 + sin(dist_t * PI) * 0.22

	var coin_text = "COINS %d" % coins
	var dist_text = "DIST %d m" % int(_distance_m)

	var coin_size = int(42.0 * _coin_pop_scale)
	var dist_size = int(34.0 * dist_scale)

	var coin_y = 46.0 + sin(_elapsed * 5.0) * 1.5
	var dist_y = 96.0 + sin(_elapsed * 3.2) * 1.0

	var coin_color = Color(1.0, 0.9, 0.18) if _coin_pop_timer > 0.0 else Color(1.0, 0.82, 0.28)
	var dist_color = Color(0.45, 1.0, 0.72) if _dist_bump_timer > 0.0 else Color(0.72, 1.0, 0.84)

	_draw_big_text(font, coin_text, Vector2(0.0, coin_y), coin_size, coin_color)
	_draw_big_text(font, dist_text, Vector2(0.0, dist_y), dist_size, dist_color)

	if _coin_pop_timer > 0.0:
		var fade = clamp(_coin_pop_timer / 0.5, 0.0, 1.0)
		var rise = (1.0 - fade) * 34.0
		_draw_big_text(
			font,
			"+%d" % max(coins, 1),
			Vector2(165.0, coin_y - 8.0 - rise),
			22,
			Color(1.0, 0.95, 0.35, fade)
		)

func _draw_big_text(font: Font, text: String, pos: Vector2, font_size: int, color: Color) -> void:
	draw_string(
		font,
		pos + Vector2(3.0, 3.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color(0.0, 0.0, 0.0, 0.55)
	)

	draw_string(
		font,
		pos,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		color
	)