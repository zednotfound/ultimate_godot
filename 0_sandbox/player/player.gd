#########################################
##  Starter Controller by GameDev.tv   ##
#########################################

# Bare-bones First Person Character Controller for the GameDev.tv Ultimate Godot Program
# Use this as a starting point for your player at the start of the program

# Installation Instructions:
# 1. Download the project files and unzip them.
# 2. Open the project folder in the file explorer.
# 3. Locate the starter_controller folder.
# 4. Copy the starter_controller.tscn and starter_controller.gd into your own project.

# License: CC0

extends CharacterBody3D

# Debug
@export var debug_info := false

# Mouse
@export_group("Mouse Stuff")
@export var mouse_sensitivity := Vector2(0.15, 0.15)
@export_range(30.0, 90.0) var max_vertical_look_angle := 90.0
@export_range(-90.0, -30.0) var min_vertical_look_angle := -90.0

# Movement
@export_group("Movement")
@export var movement_acceleration = 2.0
@export var stop_drag := 0.9
@export var walk_speed := 2.5
@export var move_speed := 8.0
@export var sprint_speed := 14.0
@export var push_force = 5.0

var max_speed := 0.0
var movement_drag := 0.0
var movement_direction := Vector3.ZERO

# Gravity and Jumping
@export_group("Gravity and Jumping")
@export var gravity := 18.0
@export var jump_force := 10.0

# Onready Variables
@onready var camera_3d: Camera3D = $Camera3D


func _ready() -> void:
	# Capture the mouse at the start of the game
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Character moves at the move_speed by default
	set_new_max_speed(move_speed)


func _process(_delta: float) -> void:
	# Capture the mouse if the left mouse button is pressed
	if (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
	):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# If the ESCAPE key is pressed
	if Input.is_action_just_pressed("quit"):
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			# Quit the game if the mouse isn't captured
			get_tree().quit()
		else:
			# Release the mouse if it is currently captured
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Get the movement input as a Vector2, X is the left/right input, Y is the forward/backward
	var input_direction := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_backward"
	)

	# Calculate the movement direction, multiply with the basis
	# so that we move according to the controllers rotation
	var new_move_dir := transform.basis * Vector3(input_direction.x, 0.0, input_direction.y)

	set_movement_direction(new_move_dir)
	determine_player_move_speed()

	# Jump check
	if Input.is_action_just_pressed("jump"):
		jump()


func _physics_process(delta: float) -> void:
	# Apply gravity while the controller is not on the floor
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Using movement_drag by default
	var drag := movement_drag

	# Use the stop_drag if there is no movement direction
	if movement_direction.is_zero_approx():
		drag = stop_drag

	# Get the flat velocity -> no vertical velocity
	var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)

	# Calculate the velocity and add it to the current velocity
	var velocity_to_add: Vector3 = (
		(movement_acceleration * movement_direction) - (flat_velocity * drag)
	)
	velocity += velocity_to_add

	move_and_slide()

	if debug_info:
		print("[%s] Speed: %s" % [name, flat_velocity.length()])

	# For pushing rigid bodies around
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		if c.get_collider() is RigidBody3D:
			c.get_collider().apply_central_impulse(-c.get_normal() * push_force)


func _input(event: InputEvent) -> void:
	# Rotate the camera based on mouse motion
	if (event is InputEventMouseMotion) && (Input.mouse_mode == Input.MOUSE_MODE_CAPTURED):
		# Rotate the controller left and right based on horizontal mouse motion
		rotation_degrees.y -= event.relative.x * mouse_sensitivity.x

		# Rotate the camera up and down based on vertical mouse motion
		camera_3d.rotation_degrees.x -= event.relative.y * mouse_sensitivity.y

		# Clamp the camera rotation between min and max look angles
		camera_3d.rotation_degrees.x = clampf(
			camera_3d.rotation_degrees.x, min_vertical_look_angle, max_vertical_look_angle
		)


func jump() -> void:
	if is_on_floor():
		velocity.y = jump_force


# Determine how if the player should be walking or sprint
func determine_player_move_speed():
	if Input.is_action_pressed("walk"):
		set_new_max_speed(walk_speed)
	elif Input.is_action_pressed("sprint"):
		set_new_max_speed(sprint_speed)
	else:
		set_new_max_speed(move_speed)


# Utility function to set the movement direction
func set_movement_direction(new_move_dir: Vector3) -> void:
	# Get rid of any vertical direction and normalize the vector
	# Normalizing it so that diagonal input doesn't move us faster
	movement_direction = Vector3(new_move_dir.x, 0.0, new_move_dir.z).normalized()


# Utility function to set a new maximum speed
func set_new_max_speed(nms: float) -> void:
	if max_speed != nms:
		max_speed = nms
		# Recalculate the movement drag
		movement_drag = movement_acceleration / max_speed
