extends Area2D

# ─── Config ───────────────────────────────────────────────────────────────────
## Base radius of the gem in pixels
@export var radius: float = 22.0

# ─── State ────────────────────────────────────────────────────────────────────
var value: int = 1
var _elapsed: float = 0.0
var _collected: bool = false

# ─── Internal: cached road reference ─────────────────────────────────────────
var _road: StaticBody2D = null
var _base_y: float = 0.0 # road surface Y at our X
var _hover_offset: float = 0.0 # randomised per-gem phase so they don't all bob in sync

func _ready() -> void:
	add_to_group("gems")
	_road = get_node_or_null("/root/main/Road")
	_hover_offset = randf_range(0.0, TAU)
	scale = Vector2(0.7, 0.7)

	body_entered.connect(_on_body_entered)
	set_process(true)

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
	if hud_stats and hud_stats.has_method("add_gem"):
		hud_stats.call("add_gem", value)

func _draw() -> void:
	if not _collected:
		_draw_gem()

func _draw_gem() -> void:
	var r = radius
	var pulse = sin(_elapsed * 5.0) * 0.04
	r *= (1.0 + pulse)
	
	var center = Vector2.ZERO
	
	# 1. Dark outer drop shadow
	var pts_shadow = PackedVector2Array([
		center + Vector2(0, -r) + Vector2(0, 2.0), # Top
		center + Vector2(r * 0.85, -r * 0.25) + Vector2(0, 2.0), # Top Right
		center + Vector2(r * 0.45, r) + Vector2(0, 2.0), # Bottom Right
		center + Vector2(-r * 0.45, r) + Vector2(0, 2.0), # Bottom Left
		center + Vector2(-r * 0.85, -r * 0.25) + Vector2(0, 2.0) # Top Left
	])
	draw_polygon(pts_shadow, PackedColorArray([Color(0.12, 0.12, 0.12, 0.6)]))
	
	# 2. Define outer coordinates of diamond gemstone
	var pts = PackedVector2Array([
		center + Vector2(0, -r), # Top
		center + Vector2(r * 0.85, -r * 0.25), # Top Right
		center + Vector2(r * 0.45, r), # Bottom Right
		center + Vector2(-r * 0.45, r), # Bottom Left
		center + Vector2(-r * 0.85, -r * 0.25) # Top Left
	])
	
	# 3. Base shading (Blue)
	draw_polygon(pts, PackedColorArray([Color("#2e86c1")]))
	
	# 4. Facet Highlight (Light Blue)
	var light_pts = PackedVector2Array([
		center + Vector2(0, -r + 4.0),
		center + Vector2(r * 0.75, -r * 0.25),
		center + Vector2(0, 0)
	])
	draw_polygon(light_pts, PackedColorArray([Color("#a9cce3")]))
	
	# 5. Outlines
	var outline_pts = PackedVector2Array()
	for pt in pts:
		outline_pts.append(pt)
	outline_pts.append(pts[0])
	draw_polyline(outline_pts, Color.BLACK, 4.0)
	
	# 6. Facet line segments
	draw_line(center + Vector2(0, -r), center + Vector2(0, 0), Color.BLACK, 1.8)
	draw_line(center + Vector2(-r * 0.85, -r * 0.25), center + Vector2(0, 0), Color.BLACK, 1.8)
	draw_line(center + Vector2(r * 0.85, -r * 0.25), center + Vector2(0, 0), Color.BLACK, 1.8)
	draw_line(center + Vector2(-r * 0.45, r), center + Vector2(0, 0), Color.BLACK, 1.8)
	draw_line(center + Vector2(r * 0.45, r), center + Vector2(0, 0), Color.BLACK, 1.8)
