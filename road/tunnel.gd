extends Node2D

func _ready() -> void:
	var area = get_node_or_null("TriggerArea")
	if area:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)

func _is_player_body(body: Node2D) -> bool:
	return body.name == "chassis" or body.name == "boat" or body.name == "truck" or (body.get_parent() and body.get_parent().name == "truck")

func _on_body_entered(body: Node2D) -> void:
	if _is_player_body(body):
		var camera = get_viewport().get_camera_2d()
		if camera:
			camera.set("inside_tunnel", true)

func _on_body_exited(body: Node2D) -> void:
	if _is_player_body(body):
		var camera = get_viewport().get_camera_2d()
		if camera:
			camera.set("inside_tunnel", false)
