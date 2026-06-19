@tool
extends Node2D

@export_group("Terrain Alignment")
@export var auto_snap_to_road := true:
	set(val):
		auto_snap_to_road = val
		snap_to_road()

@export_group("Dimensions")
@export var truck_length: float = 188.0:
	set(val):
		truck_length = val
		update_layout()

@export var plate_length: float = 120.0:
	set(val):
		plate_length = val
		update_layout()

@export var space_distance: float = 188.0:
	set(val):
		space_distance = val
		update_layout()

@export var elevator_length: float = 188.0:
	set(val):
		elevator_length = val
		update_layout()

@export_group("Movement")
@export var travel_height: float = 200.0:
	set(val):
		travel_height = val
		update_layout()

@export var raise_speed: float = 220.0 # Pixels per second
@export var lower_speed: float = 140.0 # Pixels per second

var is_pressed: bool = false
var target_y: float = 0.0

@onready var pressure_plate: Area2D = $PressurePlate
@onready var elevator: AnimatableBody2D = $Elevator

func snap_to_road() -> void:
	if not auto_snap_to_road or not is_inside_tree():
		return
	var road = get_parent().get_node_or_null("Road")
	if road and road.has_method("get_road_height"):
		var target_y_val = road.call("get_road_height", position.x)
		if position.y != target_y_val:
			position.y = target_y_val

func _ready() -> void:
	update_layout()
	if not Engine.is_editor_hint():
		is_pressed = false
		if elevator:
			elevator.position.y = 0.0

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		update_layout()
		return
		
	if not elevator:
		return
		
	# Determine target Y based on whether the plate is stepped on
	target_y = -travel_height if is_pressed else 0.0
	
	var current_y = elevator.position.y
	var diff = target_y - current_y
	
	if abs(diff) > 0.1:
		elevator.is_moving = true
		var speed = raise_speed if is_pressed else lower_speed
		var move = sign(diff) * speed * delta
		
		if abs(move) > abs(diff):
			elevator.position.y = target_y
		else:
			elevator.position.y += move
	else:
		elevator.position.y = target_y
		elevator.is_moving = false

func _on_plate_state_changed(active: bool) -> void:
	is_pressed = active

func update_layout() -> void:
	snap_to_road()
	var plate = get_node_or_null("PressurePlate")
	var plate_shape = get_node_or_null("PressurePlate/CollisionShape2D")
	var elev = get_node_or_null("Elevator")
	var elev_shape = get_node_or_null("Elevator/CollisionShape2D")
	
	if plate:
		plate.set("plate_length", plate_length)
		# Centered at plate_length / 2, resting on ground Y = 0
		plate.position = Vector2(plate_length / 2.0, 0.0)
		
	if plate_shape:
		var rect = plate_shape.shape as RectangleShape2D
		if not rect:
			rect = RectangleShape2D.new()
			plate_shape.shape = rect
		else:
			rect = rect.duplicate() as RectangleShape2D
			plate_shape.shape = rect
		rect.size = Vector2(plate_length, 20.0)
		plate_shape.position = Vector2(0.0, -10.0) # Bottom matches Y = 0
		
	if elev:
		elev.set("elevator_length", elevator_length)
		# Centered at (plate_length + space_distance + elevator_length / 2)
		elev.position.x = plate_length + space_distance + elevator_length / 2.0
		# In editor, keep preview Y at 0
		if Engine.is_editor_hint() and elev.position.y != 0.0:
			elev.position.y = 0.0
			
	if elev_shape:
		var rect = elev_shape.shape as RectangleShape2D
		if not rect:
			rect = RectangleShape2D.new()
			elev_shape.shape = rect
		else:
			rect = rect.duplicate() as RectangleShape2D
			elev_shape.shape = rect
		rect.size = Vector2(elevator_length, 12.0)
		elev_shape.position = Vector2(0.0, 6.0) # Top surface matches Y = 0
