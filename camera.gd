extends Camera2D

@export var target_path: NodePath
var target: Node2D

var default_zoom := Vector2(1.2, 1.2)
var zoomed_zoom := Vector2(1.8, 1.8)

func _ready():
	if target_path:
		target = get_node(target_path) as Node2D
	else:
		# Search for the chassis automatically in the scene tree
		target = get_node_or_null("../truck/chassis")

func _physics_process(delta):
	if is_instance_valid(target):
		# Interpolate position smoothly to center the truck in the camera view
		global_position = global_position.lerp(target.global_position, 10.0 * delta)
		
		# Smoothly interpolate zoom based on truck zoom request
		var target_zoom = default_zoom
		var truck = get_node_or_null("../truck")
		if truck and truck.has_method("is_zoom_requested") and truck.is_zoom_requested():
			target_zoom = zoomed_zoom
			
		zoom = zoom.lerp(target_zoom, 5.0 * delta)
