extends Area2D

# ─── Config ───────────────────────────────────────────────────────────────────
## How much fuel (0-100 scale) this can restores on pickup
@export_range(5.0, 100.0, 5.0) var refuel_amount: float = 30.0

# ─── State ────────────────────────────────────────────────────────────────────
var _elapsed: float = 0.0
var _collected: bool = false
var _hover_offset: float = 0.0

# ─── Internal: cached road reference ─────────────────────────────────────────
var _road: Node = null
var _base_y: float = 0.0

func _ready() -> void:
	add_to_group("petrol_cans")
	_road = get_node_or_null("/root/main/Road")
	_hover_offset = randf_range(0.0, TAU)
	body_entered.connect(_on_body_entered)
	set_process(true)

func _process(delta: float) -> void:
	_elapsed += delta

	if _collected:
		queue_free()
		return

	if _road and _road.has_method("get_road_height"):
		_base_y = _road.call("get_road_height", global_position.x)

	# Hover gently above road — slightly slower bob than coins for distinction
	var hover = sin(_elapsed * 2.5 + _hover_offset) * 10.0 - 36.0
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

	# Disable collision immediately
	var col = get_node_or_null("CollisionShape2D")
	if col:
		col.set_deferred("disabled", true)

	# Fill the HUD petrol bar
	var hud_stats = get_node_or_null("/root/main/truck/HUD/HudStats")
	if hud_stats and hud_stats.has_method("fill_petrol"):
		hud_stats.call("fill_petrol", refuel_amount)

func _draw() -> void:
	if _collected:
		return
	_draw_petrol_can()

# ── Draw a stylised jerry-can ─────────────────────────────────────────────────
func _draw_petrol_can() -> void:
	var pulse = sin(_elapsed * 4.0) * 0.03
	var scale_f = 1.0 + pulse

	# Colours — industrial red with orange highlight
	var col_body  = Color(0.75, 0.12, 0.08)
	var col_hi    = Color(0.95, 0.38, 0.22)
	var col_dark  = Color(0.45, 0.05, 0.03)
	var col_cap   = Color(0.85, 0.78, 0.15)   # yellow nozzle cap
	var col_label = Color(1.0, 0.94, 0.0, 0.9)

	var w: float = 24.0 * scale_f
	var h: float = 30.0 * scale_f

	# Drop shadow
	draw_rect(Rect2(-w * 0.5 + 1.5, -h * 0.5 + 2.5, w, h), Color(0, 0, 0, 0.40), true, 0.0, true)

	# Can body
	draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), col_body, true, 0.0, true)

	# Right-side highlight strip
	var hi_rect = Rect2(-w * 0.5 + w * 0.65, -h * 0.5 + 3.0, w * 0.15, h - 6.0)
	draw_rect(hi_rect, col_hi, true, 0.0, true)

	# Dark left-side shading
	var dk_rect = Rect2(-w * 0.5, -h * 0.5 + 3.0, w * 0.12, h - 6.0)
	draw_rect(dk_rect, col_dark, true, 0.0, true)

	# Nozzle cap on top-right
	var cap_w: float = w * 0.30
	var cap_h: float = 7.0 * scale_f
	draw_rect(Rect2(w * 0.5 - cap_w, -h * 0.5 - cap_h, cap_w, cap_h), col_cap, true, 0.0, true)
	draw_rect(Rect2(w * 0.5 - cap_w, -h * 0.5 - cap_h, cap_w, cap_h), col_dark.lightened(0.1), false, 1.0, true)

	# Handle on top-left (simple arch)
	var handle_x = -w * 0.5 + 2.0
	draw_line(Vector2(handle_x, -h * 0.5), Vector2(handle_x - 5.0 * scale_f, -h * 0.5 - 8.0 * scale_f), col_dark.lightened(0.15), 2.5)
	draw_line(Vector2(handle_x - 5.0 * scale_f, -h * 0.5 - 8.0 * scale_f), Vector2(handle_x + w * 0.35, -h * 0.5 - 8.0 * scale_f), col_dark.lightened(0.15), 2.5)
	draw_line(Vector2(handle_x + w * 0.35, -h * 0.5 - 8.0 * scale_f), Vector2(handle_x + w * 0.35, -h * 0.5), col_dark.lightened(0.15), 2.5)

	# Centre label — fuel drop symbol
	var drop_mid = Vector2(0.0, 0.0)
	draw_line(drop_mid + Vector2(0, -7.0 * scale_f), drop_mid + Vector2(0, 5.0 * scale_f), col_label, 2.0)
	draw_circle(drop_mid + Vector2(0, 5.5 * scale_f), 4.0 * scale_f, col_label)

	# Outer border
	draw_rect(Rect2(-w * 0.5, -h * 0.5, w, h), col_dark, false, 1.5, true)

	# Glow halo (subtle warm aura)
	var glow_a = (0.5 + sin(_elapsed * 5.0) * 0.3) * 0.25
	draw_circle(Vector2.ZERO, (w * 0.75) * scale_f, Color(1.0, 0.5, 0.1, glow_a))
