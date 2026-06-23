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
		# Interpolate horizontal offset dynamically (combat transition shift)
		horizontal_offset = lerp(horizontal_offset, target_horizontal_offset, 3.0 * delta)
		
		# Interpolate position smoothly to center the truck in the camera view with offsets
		var target_pos = target.global_position + Vector2(horizontal_offset, vertical_offset)
		global_position = global_position.lerp(target_pos, 10.0 * delta)
		
		# Smoothly interpolate zoom based on tunnel state or truck zoom request
		var target_zoom = default_zoom
		if inside_tunnel:
			target_zoom = tunnel_zoom
		else:
			var truck = get_node_or_null("../truck")
			if truck and truck.has_method("is_zoom_requested") and truck.is_zoom_requested():
				target_zoom = zoomed_zoom
			
		zoom = zoom.lerp(target_zoom, 5.0 * delta)
