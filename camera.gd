extends Camera2D

@export var target_path: NodePath
var target: Node2D

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
