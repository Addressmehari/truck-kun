extends Area2D

# ─── Config ───────────────────────────────────────────────────────────────────
## How many coins this pickup is worth
@export var value: int = 1
## Base radius of the coin disc in pixels
@export var radius: float = 11.0

# ─── State ────────────────────────────────────────────────────────────────────
var _elapsed: float = 0.0
var _collected: bool = false
var _collect_timer: float = 0.0   # drives the pop-out burst animation
const COLLECT_ANIM_DURATION: float = 0.45

# ─── Internal: cached road reference ─────────────────────────────────────────
var _road: StaticBody2D = null
var _base_y: float = 0.0          # road surface Y at our X
var _hover_offset: float = 0.0    # randomised per-coin phase so they don't all bob in sync

func _ready() -> void:
	add_to_group("coins")
	# Cache road reference for hover snapping
	_road = get_node_or_null("/root/main/Road")
	_hover_offset = randf_range(0.0, TAU)

	# Connect body_entered signal to detect truck / chassis touch
	body_entered.connect(_on_body_entered)

	# Force the child Node2D to redraw every frame
	set_process(true)

func _process(delta: float) -> void:
	_elapsed += delta

	if _collected:
		_collect_timer -= delta
		if _collect_timer <= 0.0:
			queue_free()
			return
	else:
		# Smooth hover: float above road surface using a sine wave
		if _road and _road.has_method("get_road_height"):
			_base_y = _road.call("get_road_height", global_position.x)
		var hover = sin(_elapsed * 3.2 + _hover_offset) * 5.0 - 18.0
		position.y = _base_y + hover

	# Gentle spin around Y axis simulated via X-scale flicker (2D trick)
	var spin_scale = cos(_elapsed * 4.5)
	scale.x = abs(spin_scale) * 1.0 + 0.001   # never exactly 0

	queue_redraw()

func _on_body_entered(body: Node) -> void:
	if _collected:
		return
	# Accept any body that belongs to the truck group OR named chassis / tyre
	var is_truck_part = (
		body.is_in_group("truck") or
		body.name == "chassis" or
		body.name.begins_with("tyre")
	)
	if not is_truck_part:
		return

	_collected = true
	_collect_timer = COLLECT_ANIM_DURATION

	# Disable collision immediately so it can't be double-collected
	var col = get_node_or_null("CollisionShape2D")
	if col:
		col.set_deferred("disabled", true)

	# Award the coin in HudStats
	var hud_stats = get_node_or_null("/root/main/truck/HUD/HudStats")
	if hud_stats and hud_stats.has_method("add_coin"):
		hud_stats.call("add_coin", value)

func _draw() -> void:
	if _collected:
		_draw_collect_burst()
	else:
		_draw_coin()

# ── Draw the coin disc ────────────────────────────────────────────────────────
func _draw_coin() -> void:
	var r = radius
	var pulse = sin(_elapsed * 5.0) * 0.08
	r *= (1.0 + pulse)

	# Outer glow halo
	draw_circle(Vector2.ZERO, r + 6.0, Color(1.0, 0.85, 0.05, 0.18))

	# Coin body gradient (two layers for a bevelled look)
	draw_circle(Vector2.ZERO, r, Color(0.92, 0.68, 0.04))
	draw_circle(Vector2.ZERO, r - 2.5, Color(1.0, 0.88, 0.32))

	# Specular highlight (top-left crescent)
	draw_circle(Vector2(-r * 0.28, -r * 0.28), r * 0.38, Color(1.0, 1.0, 0.82, 0.55))

	# Dark rim for depth
	draw_arc(Vector2.ZERO, r - 0.5, 0.0, TAU, 32, Color(0.55, 0.38, 0.0, 0.6), 1.5)

	# Centre symbol — a simple "$" star shape made of 4 lines
	var arm = r * 0.42
	var sym_color = Color(0.65, 0.42, 0.0, 0.85)
	draw_line(Vector2(0, -arm), Vector2(0, arm), sym_color, 2.0)
	draw_line(Vector2(-arm * 0.7, -arm * 0.5), Vector2(arm * 0.7, arm * 0.5), sym_color, 1.5)
	draw_line(Vector2(arm * 0.7, -arm * 0.5), Vector2(-arm * 0.7, arm * 0.5), sym_color, 1.5)

# ── Draw the collect burst (sparkle pop-out then fade) ─────────────────────────
func _draw_collect_burst() -> void:
	var t = 1.0 - clamp(_collect_timer / COLLECT_ANIM_DURATION, 0.0, 1.0)  # 0→1 as anim plays
	var fade = 1.0 - t
	var expand = t

	# Shockwave ring
	var ring_r = radius + expand * 28.0
	draw_arc(Vector2.ZERO, ring_r, 0, TAU, 48,
		Color(1.0, 0.88, 0.15, fade * 0.75), 3.0 * (1.0 - expand))

	# Burst particles — 8 rays fanning outward
	for i in range(8):
		var angle = float(i) / 8.0 * TAU + _elapsed * 2.0
		var length = expand * 26.0
		var start = Vector2(cos(angle), sin(angle)) * (radius * 0.5)
		var end   = Vector2(cos(angle), sin(angle)) * (radius * 0.5 + length)
		var c = Color(1.0, 0.92, 0.22, fade * 0.90) if i % 2 == 0 else Color(1.0, 1.0, 0.70, fade * 0.60)
		draw_line(start, end, c, 2.5)

	# Central coin fading out
	var r_fade = radius * (1.0 - expand * 0.5)
	draw_circle(Vector2.ZERO, r_fade, Color(1.0, 0.90, 0.30, fade))
