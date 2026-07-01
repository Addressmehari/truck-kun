extends Node2D

var _has_triggered_biome_change := false
var _has_triggered_entrance := false

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
			
		if not _has_triggered_entrance:
			_has_triggered_entrance = true
			var road = get_node_or_null("/root/main/Road")
			if road and road.has_method("prepare_next_biome"):
				road.call("prepare_next_biome")

func _on_body_exited(body: Node2D) -> void:
	if _is_player_body(body):
		var camera = get_viewport().get_camera_2d()
		if camera:
			camera.set("inside_tunnel", false)
		
		# If they exited to the right (crossed the tunnel), change the biome!
		if body.global_position.x > global_position.x and not _has_triggered_biome_change:
			_has_triggered_biome_change = true
			var road = get_node_or_null("/root/main/Road")
			if road and road.has_method("cycle_biome"):
				road.call("cycle_biome")
