extends Node

# ─── Tuning ───────────────────────────────────────────────────────────────────
## Minimum world-X gap between any two consecutive coins (pixels)
@export var min_spacing: float = 360.0
## Maximum world-X gap between consecutive coins (pixels)
@export var max_spacing: float = 840.0
## How many coins to keep pre-spawned ahead of the chassis
@export var pool_size: int = 10
## How far ahead of the chassis to pre-spawn coins (pixels)
@export var spawn_lead: float = 1200.0
## How far behind chassis before a coin is removed (pixels)
@export var despawn_trail: float = 600.0
## Chance (0-1) that the next slot gets a triple-coin cluster instead of single
@export_range(0.0, 1.0, 0.05) var cluster_chance: float = 0.22
## Base chance (0-1) that the next slot spawns a petrol can instead of coins
@export_range(0.0, 0.5, 0.02) var petrol_chance: float = 0.10
## Minimum gap (pixels) since last petrol can spawn before another can spawn
@export var min_petrol_spacing: float = 3000.0
## Fuel ratio (0-1) below which we start spawning petrol cans
@export var petrol_spawn_threshold: float = 0.70
## Fuel ratio (0-1) below which we force spawn a petrol can if none are ahead
@export var petrol_critical_threshold: float = 0.25
## Chance (0-1) that the next slot spawns a mystery box
@export_range(0.0, 0.5, 0.01) var mystery_box_chance: float = 0.05
## Y offset above road surface so coins hover visibly
@export var hover_height: float = -20.0
## Minimum cooldown duration (seconds) after a mini-event ends before mystery boxes can spawn again
@export var min_cooldown_duration: float = 25.0
## Maximum cooldown duration (seconds) after a mini-event ends before mystery boxes can spawn again
@export var max_cooldown_duration: float = 35.0

# ─── Internal ─────────────────────────────────────────────────────────────────
var _coin_scene: PackedScene
var _petrol_scene: PackedScene
var _mystery_box_scene: PackedScene
var _road: StaticBody2D
var _chassis: RigidBody2D
var _coins: Array[Node] = []       # live coin nodes
var _next_spawn_x: float = 0.0     # world X where the next coin should appear
var _last_petrol_spawn_x: float = -9999.0 # world X of the last petrol can spawn
var _rng: RandomNumberGenerator
var _was_event_active: bool = false
var _cooldown_timer: float = 0.0

func _ready() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.randomize()

	# Resolve references
	_road   = get_node_or_null("/root/main/Road")
	_chassis = get_node_or_null("/root/main/truck/chassis")

	# Preload scene
	_coin_scene = load("res://obstacles/coin.tscn")
	if not _coin_scene:
		push_error("CoinSpawner: cannot load res://obstacles/coin.tscn")
		return

	_petrol_scene = load("res://obstacles/petrol.tscn")
	if not _petrol_scene:
		push_warning("CoinSpawner: petrol.tscn not found — petrol cans won't spawn")

	_mystery_box_scene = load("res://obstacles/mystery_box.tscn")
	if not _mystery_box_scene:
		push_warning("CoinSpawner: mystery_box.tscn not found — mystery boxes won't spawn")

	# Seed the first spawn position just ahead of the chassis start
	if is_instance_valid(_chassis):
		_next_spawn_x = _chassis.global_position.x + 300.0
	else:
		_next_spawn_x = 300.0

	_last_petrol_spawn_x = _next_spawn_x

	# Prime the pool
	_fill_pool()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_chassis):
		return

	# Decay cooldown timer
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta

	# Track event transitions to trigger cooldowns
	var is_event_running = false
	if _road and _road.has_method("is_event_active"):
		is_event_running = _road.call("is_event_active")
		
	if _was_event_active and not is_event_running:
		var duration = _rng.randf_range(min_cooldown_duration, max_cooldown_duration)
		_cooldown_timer = duration
		print("[CoinSpawner] Event ended! Mystery box spawn cooldown active for %.1f seconds" % duration)
		
	_was_event_active = is_event_running

	var chassis_x = _chassis.global_position.x

	# ── Despawn coins left far behind ─────────────────────────────────────────
	var i = _coins.size() - 1
	while i >= 0:
		var c = _coins[i]
		if not is_instance_valid(c):
			_coins.remove_at(i)
		elif c.global_position.x < chassis_x - despawn_trail:
			c.queue_free()
			_coins.remove_at(i)
		i -= 1

	# ── Spawn new coins until the pool is full ahead of the player ────────────
	_fill_pool()

# ── Spawn until we have pool_size coins within spawn_lead ahead ───────────────
func _fill_pool() -> void:
	if not _coin_scene:
		return

	var chassis_x = 0.0
	if is_instance_valid(_chassis):
		chassis_x = _chassis.global_position.x

	# Ensure the next spawn frontier is always safely ahead of the player
	if _next_spawn_x < chassis_x + 300.0:
		_next_spawn_x = chassis_x + 300.0

	# ── Pause ALL normal spawning while a mini-event is active ────────────────
	# (Convoy, Crusher, Racing etc. all have their own world-generation logic)
	var is_event_running = false
	if _road and _road.has_method("is_event_active"):
		is_event_running = _road.call("is_event_active")
	if is_event_running:
		return

	# Count how many coins are still alive ahead of the player
	var ahead_count = 0
	for c in _coins:
		if is_instance_valid(c) and c.global_position.x > chassis_x:
			ahead_count += 1

	# During crate delivery or tow missions, always allow mystery boxes
	# (Racing is already fully paused above via is_event_running)
	var is_delivery_or_tow_active := false
	if _road:
		var dtc = _road.get("delivery_target_chunk")
		if dtc != null and dtc != -1:
			is_delivery_or_tow_active = true
		if not is_delivery_or_tow_active:
			var ttc = _road.get("towing_target_chunk")
			if ttc != null and ttc != -1:
				is_delivery_or_tow_active = true
		if not is_delivery_or_tow_active:
			var tow = _road.get("is_towing_active")
			if tow == true:
				is_delivery_or_tow_active = true

	# Mystery boxes blocked during post-event cooldown — UNLESS delivery/tow is active
	var mystery_box_blocked: bool = (_cooldown_timer > 0.0) and not is_delivery_or_tow_active

	while ahead_count < pool_size and _next_spawn_x < chassis_x + spawn_lead:
		var roll = _rng.randf()

		# Check if this spawn X is within the tunnel spawn shield (inside or 100m before the tunnel)
		var in_tunnel_shield := false
		if _road and _road.has_method("is_in_tunnel_spawn_shield"):
			in_tunnel_shield = _road.is_in_tunnel_spawn_shield(_next_spawn_x)
			
		if in_tunnel_shield:
			# Suppress spawns, just advance the frontier
			_next_spawn_x += _rng.randf_range(min_spacing, max_spacing)
			continue

		# Resolve whether this spawn X falls inside a bridge canyon — mystery boxes
		# are suppressed there because get_road_height() returns the canyon floor,
		# not the bridge deck, so the box would spawn far below the playable surface.
		var in_bridge_zone := false
		if _road and _road.has_method("is_in_bridge_zone"):
			in_bridge_zone = _road.call("is_in_bridge_zone", _next_spawn_x, 150.0)

		# ── SMART PETROL CALCULATIONS ──
		var spawn_petrol_here := false
		var fuel_ratio := 1.0
		var dist_since_last_petrol := 999999.0
		var has_petrol_ahead := false

		if _petrol_scene and not in_bridge_zone:
			var hud_stats = get_node_or_null("/root/main/truck/HUD/HudStats")
			if hud_stats and "petrol" in hud_stats and "petrol_max" in hud_stats:
				var max_p = hud_stats.petrol_max
				if max_p > 0.0:
					fuel_ratio = hud_stats.petrol / max_p
			
			dist_since_last_petrol = _next_spawn_x - _last_petrol_spawn_x
			has_petrol_ahead = _has_active_petrol_ahead(chassis_x)

			# Emergency Force Spawn: if critically low on fuel (<25%) and no petrol can is ahead
			if fuel_ratio < petrol_critical_threshold and not has_petrol_ahead:
				if dist_since_last_petrol > 1200.0:
					spawn_petrol_here = true
					print("[CoinSpawner] EMERGENCY SPAWN: Fuel is critical (%.1f%%). Forcing petrol can spawn at X=%.1f" % [fuel_ratio * 100.0, _next_spawn_x])
			# Normal/Smart spawning mode: fuel is below threshold
			elif fuel_ratio < petrol_spawn_threshold:
				if dist_since_last_petrol > min_petrol_spacing and not has_petrol_ahead:
					# Scale chance dynamically based on fuel ratio (base_chance at threshold to 2.5x base_chance at critical)
					var t = (petrol_spawn_threshold - fuel_ratio) / (petrol_spawn_threshold - petrol_critical_threshold)
					t = clamp(t, 0.0, 1.0)
					var dynamic_chance = lerp(petrol_chance, petrol_chance * 2.5, t)
					
					if _rng.randf() < dynamic_chance:
						spawn_petrol_here = true
						print("[CoinSpawner] SMART SPAWN: Fuel ratio %.2f, dynamic chance %.2f%%. Spawning petrol can at X=%.1f" % [fuel_ratio, dynamic_chance * 100.0, _next_spawn_x])

		# ── Obstacle Selection ──
		if not mystery_box_blocked and not in_bridge_zone and _mystery_box_scene and roll < mystery_box_chance:
			# Mystery box — only when no active event and cooldown has expired
			_spawn_mystery_box(_next_spawn_x)
			ahead_count += 1
		elif spawn_petrol_here:
			# Petrol can — placed dynamically based on player's fuel state
			_spawn_petrol(_next_spawn_x)
			_last_petrol_spawn_x = _next_spawn_x
			ahead_count += 1
		elif _rng.randf() < cluster_chance:
			_spawn_cluster(_next_spawn_x)
			ahead_count += 3
		else:
			_spawn_coin(_next_spawn_x)
			ahead_count += 1

		# Advance the frontier
		_next_spawn_x += _rng.randf_range(min_spacing, max_spacing)

# ── Spawn a single coin at world X ────────────────────────────────────────────
func _spawn_coin(world_x: float, x_jitter: float = 0.0) -> void:
	var coin = _coin_scene.instantiate()
	get_parent().add_child.call_deferred(coin)

	var spawn_x = world_x + x_jitter
	var road_y = 0.0
	if _road and _road.has_method("get_road_height"):
		road_y = _road.call("get_road_height", spawn_x)

	coin.global_position = Vector2(spawn_x, road_y + hover_height)
	_coins.append(coin)

# ── Spawn a tight triangle cluster of 3 coins ─────────────────────────────────
func _spawn_cluster(world_x: float) -> void:
	# Three coins: centre, slightly left, slightly right — staggered Y
	_spawn_coin(world_x, 0.0)
	_spawn_coin(world_x, -38.0)
	_spawn_coin(world_x,  38.0)

# ── Spawn a petrol can at world X ─────────────────────────────────────────────
func _spawn_petrol(world_x: float) -> void:
	if not _petrol_scene:
		return
	var can = _petrol_scene.instantiate()
	get_parent().add_child.call_deferred(can)
	var road_y = 0.0
	if _road and _road.has_method("get_road_height"):
		road_y = _road.call("get_road_height", world_x)
	can.global_position = Vector2(world_x, road_y + hover_height - 8.0)
	_coins.append(can)  # reuse the same tracking array for lifecycle management

# ── Spawn a mystery box at world X ────────────────────────────────────────────
func _spawn_mystery_box(world_x: float) -> void:
	if not _mystery_box_scene:
		return
	var box = _mystery_box_scene.instantiate()
	get_parent().add_child.call_deferred(box)
	var road_y = 0.0
	if _road and _road.has_method("get_road_height"):
		road_y = _road.call("get_road_height", world_x)
	box.global_position = Vector2(world_x, road_y + hover_height - 15.0)
	_coins.append(box) # reuse the same tracking array for lifecycle management

# ── Helper to check if any active petrol can is spawned ahead of the player ─────
func _has_active_petrol_ahead(chassis_x: float) -> bool:
	for c in _coins:
		if is_instance_valid(c) and c.is_in_group("petrol_cans") and c.global_position.x > chassis_x:
			return true
	return false
