extends Area2D

# ─── Config ───────────────────────────────────────────────────────────────────
## Base radius of the coin disc in pixels (Doubled from original)
@export var radius: float = 22.0

# ─── State ────────────────────────────────────────────────────────────────────
var value: int = 1
var _elapsed: float = 0.0
var _collected: bool = false

# Visual properties determined by the assigned tier
var _color_main: Color
var _color_inner: Color
var _color_gem_dark: Color
var _color_gem_light: Color

# ─── Internal: cached road reference ─────────────────────────────────────────
var _road: StaticBody2D = null
var _base_y: float = 0.0 # road surface Y at our X
var _hover_offset: float = 0.0 # randomised per-coin phase so they don't all bob in sync

func _ready() -> void:
	add_to_group("coins")
	_road = get_node_or_null("/root/main/Road")
	_hover_offset = randf_range(0.0, TAU)
	scale = Vector2(0.7, 0.7)

	# Determine coin tier via Gaussian Distribution
	_initialize_coin_tier()

	body_entered.connect(_on_body_entered)
	set_process(true)

func _initialize_coin_tier() -> void:
	# Box-Muller transform to generate a standard normal distribution variable (mean=0, std_dev=1)
	var u1 = randf()
	if u1 < 0.0001: u1 = 0.0001 # Avoid log(0)
	var u2 = randf()
	var standard_normal = sqrt(-2.0 * log(u1)) * cos(TAU * u2)
	
	# Shift distribution so most values are positive. Absolute value helps capture extreme spikes
	var roll = abs(standard_normal)

	# Assign tier based on distance from the mean (Standard Deviations)
	# |Z| probability reference:
	#   >= 3.8  →  ~0.01%  → Red   (Ultra Rare, ~1 in 10,000 coins)
	#   >= 3.0  →  ~0.27%  → Blue  (Rare,       ~1 in 370 coins)
	#   >= 2.5  →  ~1.2%   → Green (Uncommon,   ~1 in 83 coins)
	#   else    →  ~98.5%  → Gold  (Common)
	if roll >= 3.8:
		# Red (Ultra Rare)
		value = 500
		_color_main = Color(0.65, 0.05, 0.05)
		_color_inner = Color(0.95, 0.25, 0.25)
		_color_gem_dark = Color(0.5, 0.0, 0.0)
		_color_gem_light = Color(1.0, 0.7, 0.7)
	elif roll >= 3.0:
		# Blue (Rare)
		value = 50
		_color_main = Color(0.05, 0.35, 0.65)
		_color_inner = Color(0.25, 0.65, 0.95)
		_color_gem_dark = Color(0.0, 0.2, 0.5)
		_color_gem_light = Color(0.7, 0.9, 1.0)
	elif roll >= 2.5:
		# Green (Uncommon)
		value = 12
		_color_main = Color(0.05, 0.55, 0.15)
		_color_inner = Color(0.25, 0.85, 0.35)
		_color_gem_dark = Color(0.0, 0.4, 0.1)
		_color_gem_light = Color(0.7, 1.0, 0.8)
	else:
		# Gold (Common) — ~98.5% of all spawns
		value = 2
		_color_main = Color(0.88, 0.60, 0.02)
		_color_inner = Color(1.0, 0.88, 0.28)
		_color_gem_dark = Color(0.72, 0.44, 0.0)
		_color_gem_light = Color(1.0, 0.95, 0.6)

func _process(delta: float) -> void:
	_elapsed += delta

	if _collected:
		queue_free()
		return

	if _road and _road.has_method("get_road_height"):
		_base_y = _road.call("get_road_height", global_position.x)
	
	var hover = sin(_elapsed * 3.2 + _hover_offset) * 12.0 - 45.0
	position.y = _base_y + hover

	queue_redraw()

func _on_body_entered(body: Node) -> void:
	if _collected:
		return
	var is_truck_part = (
		body.is_in_group("truck") or
		body.name == "chassis" or
		body.name == "boat" or
		body.name.begins_with("tyre")
	)
	if not is_truck_part:
		return

	_collected = true

	var col = get_node_or_null("CollisionShape2D")
	if col:
		col.set_deferred("disabled", true)

	var hud_stats = get_node_or_null("/root/main/truck/HUD/HudStats")
	if hud_stats and hud_stats.has_method("add_coin"):
		hud_stats.call("add_coin", value)

func _draw() -> void:
	if not _collected:
		_draw_coin()

# ── Draw the coin disc ────────────────────────────────────────────────────────
func _draw_coin() -> void:
	var r = radius
	var pulse = sin(_elapsed * 5.0) * 0.04
	r *= (1.0 + pulse)

	# 1. Dark outer rim drop shadow for 3D depth
	draw_circle(Vector2(0, 2.0), r, Color(0.12, 0.12, 0.12, 0.6))

	# 2. Outer Base Coin Body
	draw_circle(Vector2.ZERO, r, _color_main)

	# 3. Inner Face
	draw_circle(Vector2.ZERO, r - 4.5, _color_inner)

	# 4. Inner decorative concentric groove ring
	draw_arc(Vector2.ZERO, r - 7.5, 0.0, TAU, 36, _color_main.lerp(Color.BLACK, 0.1), 1.5)

	# 5. Smooth specular gloss highlight (top-left crescent)
	draw_circle(Vector2(-r * 0.25, -r * 0.25), r * 0.4, Color(1.0, 1.0, 1.0, 0.4))

	# 6. High-contrast crisp outer rim border
	draw_arc(Vector2.ZERO, r - 0.75, 0.0, TAU, 40, _color_main.lerp(Color.BLACK, 0.4), 2.5)

	# 7. Premium Geometric Inside Design: Layered Diamond Core
	var d_size = r * 0.40
	var d_shadow = Color(0.0, 0.0, 0.0, 0.35)
	
	var d_top = Vector2(0, -d_size)
	var d_bottom = Vector2(0, d_size)
	var d_left = Vector2(-d_size, 0)
	var d_right = Vector2(d_size, 0)
	
	# Diamond Shadow Offset
	var s_off = Vector2(0, 1.5)
	draw_colored_polygon(PackedVector2Array([d_top + s_off, d_right + s_off, d_bottom + s_off, d_left + s_off]), d_shadow)
	
	# Diamond Left Facet (Darker shade)
	draw_colored_polygon(PackedVector2Array([d_top, Vector2.ZERO, d_bottom, d_left]), _color_gem_dark)
	
	# Diamond Right Facet (Lighter shade)
	draw_colored_polygon(PackedVector2Array([d_top, d_right, d_bottom, Vector2.ZERO]), _color_gem_light)
	
	# Diamond Center Dividing/Border Lines
	var border_color = _color_main.lerp(Color.BLACK, 0.5)
	draw_line(d_top, d_bottom, border_color, 1.5)
	draw_line(d_left, d_right, border_color, 1.5)
	draw_polyline(PackedVector2Array([d_top, d_right, d_bottom, d_left, d_top]), border_color, 2.0)