extends Node2D

var body_a: RigidBody2D
var body_b: RigidBody2D
var offset_a: Vector2 = Vector2.ZERO
var offset_b: Vector2 = Vector2.ZERO

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if is_instance_valid(body_a) and is_instance_valid(body_b):
		var p_a = body_a.global_position + offset_a.rotated(body_a.global_rotation)
		var p_b = body_b.global_position + offset_b.rotated(body_b.global_rotation)
		
		var local_a = to_local(p_a)
		var local_b = to_local(p_b)
		
		# Glowing safety orange tow strap
		var strap_color = Color("#ff6600")
		var shadow_color = Color(0, 0, 0, 0.4)
		
		# 1. Drop shadow line
		draw_line(local_a + Vector2(0, 2), local_b + Vector2(0, 2), shadow_color, 4.0)
		# 2. Main outer line
		draw_line(local_a, local_b, strap_color.lightened(0.2), 3.0)
		# 3. Core highlight line
		draw_line(local_a, local_b, strap_color, 1.5)
