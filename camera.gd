extends Camera2D

@export var target_path: NodePath
var target: Node2D

@export var default_zoom := Vector2(1.8, 1.8)
@export var zoomed_zoom := Vector2(2.6, 2.6)
@export var tunnel_zoom := Vector2(3.2, 3.2) # Zoomed in closer for the tunnel
@export var vertical_offset := -50.0 # Vertical offset from target (negative moves camera up)
@export var horizontal_offset := 150.0 # Horizontal offset from target (positive moves camera right, placing truck on the left)

var inside_tunnel := false
var target_horizontal_offset := 220.0

func _ready():
	if target_path:
		target = get_node(target_path) as Node2D
	else:
		# Search for the chassis automatically in the scene tree
		target = get_node_or_null("../truck/chassis")
	target_horizontal_offset = horizontal_offset

func _physics_process(delta):
	if is_instance_valid(target):
		# Determine target offset and zoom based on active event states
		var active_offset = target_horizontal_offset
		var active_zoom = default_zoom
		
		var road = get_node_or_null("../Road")
		var is_towing = road and road.get("is_towing_active") == true
		
		if is_towing:
			active_offset = 60.0 # Shift camera left to show towed car behind truck
			active_zoom = Vector2(1.4, 1.4) # Zoom out slightly for wider view
			
		# Interpolate horizontal offset dynamically
		horizontal_offset = lerp(horizontal_offset, active_offset, 1.5 * delta)
		
		var truck = get_node_or_null("../truck")
		var is_respawning = false
		if truck and is_instance_valid(truck):
			is_respawning = truck.get("is_respawning") == true
			
		if not is_respawning:
			# Interpolate position smoothly to center the truck in the camera view with offsets
			var target_pos = target.global_position + Vector2(horizontal_offset, vertical_offset)
			if not is_nan(target_pos.x) and not is_nan(target_pos.y):
				global_position = global_position.lerp(target_pos, 10.0 * delta)
		
		# Smoothly interpolate zoom based on towing or zoom request
		var target_zoom = active_zoom
		if not inside_tunnel:
			if truck and truck.has_method("is_zoom_requested") and truck.is_zoom_requested():
				target_zoom = zoomed_zoom
			
		zoom = zoom.lerp(target_zoom, 5.0 * delta)
