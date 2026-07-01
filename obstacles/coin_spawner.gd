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
## Chance (0-1) that the next slot spawns a petrol can instead of coins
@export_range(0.0, 0.5, 0.02) var petrol_chance: float = 0.10
## Y offset above road surface so coins hover visibly
@export var hover_height: float = -20.0

# ─── Internal ─────────────────────────────────────────────────────────────────
var _coin_scene: PackedScene
var _petrol_scene: PackedScene
var _road: StaticBody2D
var _chassis: RigidBody2D
var _coins: Array[Node] = []       # live coin nodes
var _next_spawn_x: float = 0.0     # world X where the next coin should appear
var _rng: RandomNumberGenerator

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

	# Seed the first spawn position just ahead of the chassis start
	if is_instance_valid(_chassis):
		_next_spawn_x = _chassis.global_position.x + 300.0
	else:
		_next_spawn_x = 300.0

	# Prime the pool
	_fill_pool()

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(_chassis):
		return

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

	# Count how many coins are still alive ahead
	var ahead_count = 0
	for c in _coins:
		if is_instance_valid(c) and c.global_position.x > chassis_x:
			ahead_count += 1

	while ahead_count < pool_size and _next_spawn_x < chassis_x + spawn_lead:
		# Decide whether to place a petrol can, cluster, or single coin
		var roll = _rng.randf()
		if _petrol_scene and roll < petrol_chance:
			_spawn_petrol(_next_spawn_x)
			ahead_count += 1
		elif roll < petrol_chance + cluster_chance:
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
