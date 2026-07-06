@tool
extends AnimatableBody2D

@export var width := 200.0:
	set(val):
		width = val
		update_layout()

@export var height := 20.0:
	set(val):
		height = val
		update_layout()

@export var is_opponent_elevator := false:
	set(val):
		is_opponent_elevator = val
		update_layout()

@export var travel_height := 250.0
@export var speed := 150.0

var start_y := 0.0
var target_y := 0.0
var is_active := false
var is_waiting_to_fall := false
var fall_timer := 0.0

@onready var area = $Area2D
@onready var color_rect = $ColorRect
@onready var collision_shape = $CollisionShape2D

func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group("elevators")
		start_y = global_position.y
		target_y = start_y
		
		# Set collision layer and mask dynamically
		if is_opponent_elevator:
			collision_layer = 2
			collision_mask = 2
			if area:
				area.collision_layer = 2
				area.collision_mask = 2
		else:
			collision_layer = 1
			collision_mask = 1
			if area:
				area.collision_layer = 1
				area.collision_mask = 1
				
		if area:
			area.body_entered.connect(_on_body_entered)
			area.body_exited.connect(_on_body_exited)
	update_layout()

func update_layout() -> void:
	var cr = get_node_or_null("ColorRect")
	if cr:
		cr.size = Vector2(width, height)
		cr.position = Vector2(-width / 2.0, -height / 2.0)
		if is_opponent_elevator:
			cr.color = Color(0.8, 0.1, 0.4) # Neon Pink
		else:
			cr.color = Color(0.2, 0.6, 0.8) # Sleek cyber blue
		
		var border = cr.get_node_or_null("Border")
		if not border:
			border = ColorRect.new()
			border.name = "Border"
			cr.add_child(border)
		border.size = Vector2(width, 3.0)
		border.position = Vector2(0, 0)
		if is_opponent_elevator:
			border.color = Color(1.0, 0.3, 0.6) # Bright neon pink glow
		else:
			border.color = Color(0.4, 0.8, 1.0) # Light blue glowing top deck
		
	var shape_node = get_node_or_null("CollisionShape2D")
	if shape_node:
		var rect = shape_node.shape as RectangleShape2D
		if not rect:
			rect = RectangleShape2D.new()
			shape_node.shape = rect
		rect.size = Vector2(width, height)
		shape_node.position = Vector2.ZERO
		
	var area_node = get_node_or_null("Area2D")
	var area_shape = get_node_or_null("Area2D/CollisionShape2D")
	if area_node and area_shape:
		var rect = area_shape.shape as RectangleShape2D
		if not rect:
			rect = RectangleShape2D.new()
			area_shape.shape = rect
		rect.size = Vector2(width - 20.0, 30.0)
		area_shape.position = Vector2(0.0, -15.0 - height / 2.0)

func update_elevator_state() -> void:
	if not area:
		return
		
	var bodies = area.get_overlapping_bodies()
	var active = false
	
	if is_opponent_elevator:
		# Detect opponent car
		for b in bodies:
			if b is OpponentCar or b.name.begins_with("opponent") or b.get("vehicle_type") != null:
				active = true
				break
	else:
		# Detect player car parts
		var has_chassis = false
		var has_container = false
		var has_boat = false
		
		for b in bodies:
			if b.name == "boat":
				has_boat = true
			elif b.name == "chassis":
				has_chassis = true
			elif b.name == "container_body":
				has_container = true
				
		active = has_boat or (has_chassis and has_container)
	
	if active:
		is_waiting_to_fall = false
		if not is_active:
			is_active = true
			print("[Elevator] Vehicle stood on elevator, raising! (opponent=", is_opponent_elevator, ")")
	else:
		if is_active and not is_waiting_to_fall:
			is_waiting_to_fall = true
			fall_timer = 4.0
			print("[Elevator] Vehicle left elevator, waiting 4s before lowering... (opponent=", is_opponent_elevator, ")")

func _on_body_entered(body: Node2D) -> void:
	if Engine.is_editor_hint():
		return
	update_elevator_state()

func _on_body_exited(body: Node2D) -> void:
	if Engine.is_editor_hint():
		return
	update_elevator_state()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	if is_waiting_to_fall:
		fall_timer -= delta
		if fall_timer <= 0.0:
			is_active = false
			is_waiting_to_fall = false
			print("[Elevator] Wait time completed, lowering! (opponent=", is_opponent_elevator, ")")
		
	# Target Y coordinate: if active, move up by travel_height. Note: Y goes up is negative in Godot!
	var target = start_y - travel_height if is_active else start_y
	
	var current_y = global_position.y
	var diff = target - current_y
	
	if abs(diff) > 0.1:
		var move = sign(diff) * speed * delta
		if abs(move) > abs(diff):
			global_position.y = target
		else:
			global_position.y += move
	else:
		global_position.y = target
