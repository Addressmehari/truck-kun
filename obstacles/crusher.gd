extends AnimatableBody2D

@export var up_wait_time := 1.5
@export var slam_time := 0.25
@export var down_wait_time := 1.0
@export var rise_time := 0.75
@export var travel_distance := 180.0

var time_elapsed := 0.0
var start_y := 0.0
var initialized := false

func _ready() -> void:
	# Add to group so we can manage or find crushers easily if needed
	add_to_group("crushers")

func initialize_crusher_position(spawn_x: float, road_y: float) -> void:
	# The block is 80 pixels tall, centered at (0,0), so it goes from y = -40 to y = 40.
	# To make the bottom of the block (y = 40) align with road_y when fully down,
	# the origin of the crusher (0,0) must be at road_y - 40.0.
	global_position = Vector2(spawn_x, road_y - 40.0)
	start_y = global_position.y
	initialized = true

var _chassis: Node2D = null

func _physics_process(delta: float) -> void:
	# If running in editor or not initialized yet, don't move
	if Engine.is_editor_hint():
		return
		
	if not initialized:
		start_y = global_position.y
		initialized = true
		
	# Despawn when left far behind the chassis
	if not is_instance_valid(_chassis):
		_chassis = get_node_or_null("/root/main/truck/chassis")
	if is_instance_valid(_chassis):
		if global_position.x < _chassis.global_position.x - 1200.0:
			queue_free()
			return
		
	time_elapsed += delta
	var cycle_duration = up_wait_time + slam_time + down_wait_time + rise_time
	var local_time = fmod(time_elapsed, cycle_duration)
	
	var y_offset := 0.0
	
	if local_time < up_wait_time:
		# Phase 1: Wait at the top (UP)
		y_offset = travel_distance
	elif local_time < up_wait_time + slam_time:
		# Phase 2: Slam down quickly (UP -> DOWN)
		var t = (local_time - up_wait_time) / slam_time
		# Quadratic ease-in (starts slow, slams down fast)
		y_offset = lerp(travel_distance, 0.0, t * t)
	elif local_time < up_wait_time + slam_time + down_wait_time:
		# Phase 3: Wait at the bottom (DOWN)
		y_offset = 0.0
	else:
		# Phase 4: Rise up slowly (DOWN -> UP)
		var t = (local_time - (up_wait_time + slam_time + down_wait_time)) / rise_time
		# Quadratic ease-out (starts fast, slows down at the top)
		y_offset = lerp(0.0, travel_distance, t * (2.0 - t))
		
	# Move the animatable body vertically relative to start_y
	global_position.y = start_y - y_offset
