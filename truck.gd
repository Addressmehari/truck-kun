extends Node2D

@export var torque_power := 12000.0
@export var air_tilt_power := 6000.0
@export var max_angular_velocity := 45.0

@onready var chassis: RigidBody2D = $chassis
@onready var container_body: RigidBody2D = $container_body
@onready var tyre_1: RigidBody2D = $"tyre-1"
@onready var tyre_2: RigidBody2D = $"tyre-2"
@onready var tyre_3: RigidBody2D = $"tyre-3"

func _physics_process(_delta):
	# Calculate input from keyboard keys
	var move_input = 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		move_input -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		move_input += 1.0
	
	if move_input != 0:
		# Apply torque to wheels to move the truck.
		tyre_1.apply_torque(move_input * torque_power)
		tyre_2.apply_torque(move_input * torque_power)
		tyre_3.apply_torque(move_input * torque_power)
		
		# Apply opposite torque to both cab and trailer parts of the body.
		# This rotates them individually and feels very dynamic in mid-air.
		chassis.apply_torque(-move_input * air_tilt_power)
		container_body.apply_torque(-move_input * air_tilt_power * 1.5)
		
	# Synchronize wheel speeds (locked differential)
	var avg_vel = (tyre_1.angular_velocity + tyre_2.angular_velocity + tyre_3.angular_velocity) / 3.0
	tyre_1.angular_velocity = avg_vel
	tyre_2.angular_velocity = avg_vel
	tyre_3.angular_velocity = avg_vel
		
	# Cap the angular velocity of the wheels so they do not spin out of control
	tyre_1.angular_velocity = clamp(tyre_1.angular_velocity, -max_angular_velocity, max_angular_velocity)
	tyre_2.angular_velocity = clamp(tyre_2.angular_velocity, -max_angular_velocity, max_angular_velocity)
	tyre_3.angular_velocity = clamp(tyre_3.angular_velocity, -max_angular_velocity, max_angular_velocity)
