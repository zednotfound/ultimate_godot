class_name Player
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

# Gravity and Jumping
@export_group("Gravity and Jumping")
@export var gravity := 18.0
@export_range(0.1, 30.0) var min_jump_force := 5.0
@export_range(0.2, 50.0) var max_jump_force := 15.0
@export_range(0.5, 5.0) var jump_charge_time := 2.0
@export_range(1.0, 30.0) var jump_camera_stretch := 12.0
@export_range(0.2, 30.0) var air_jump_force := 10.0
@export var air_jumps := 1

var max_speed := 0.0
var movement_drag := 0.0
var movement_direction := Vector3.ZERO
var jump_charge := 0.0
var air_jumps_remaining := air_jumps
var is_crouching := false:
	set(value):
		is_crouching = value
		if not is_crouching:
			player_animation.play_backwards("crouch")
		else:
			player_animation.play("crouch")
var was_on_floor := false
var is_flying := false

@onready var camera: Camera3D = $Camera3D
@onready var camera_starting_fov := camera.fov
@onready var player_animation: AnimationPlayer = $PlayerAnimation
@onready var jump_grace_timer: Timer = $JumpGraceTimer


func _ready() -> void:
	# Capture the mouse at the start of the game
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# Character moves at the move_speed by default
	set_new_max_speed(move_speed)


func _process(delta: float) -> void:
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

	if Input.is_action_just_pressed("toggle_flight"):
		if is_flying:
			is_flying = false
		else:
			is_flying = true
			var flight_tween = create_tween()
			flight_tween.set_ease(Tween.EASE_OUT)
			flight_tween.set_trans(Tween.TRANS_QUAD)
			flight_tween.tween_property(
				self, "global_position", global_position + Vector3(0, 3.5, 0), 0.3
			)
			flight_tween.play()

	# Get the movement input as a Vector2, X is the left/right input, Y is the forward/backward
	var input_direction := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_backward"
	)

	# Calculate the movement direction, multiply with the basis
	# so that we move according to the controllers rotation
	var new_move_dir := transform.basis * Vector3(input_direction.x, 0.0, input_direction.y)

	if is_flying:
		if Input.is_action_pressed("fly_up"):
			new_move_dir += Vector3(0, 1, 0)

		if Input.is_action_pressed("fly_down"):
			new_move_dir += Vector3(0, -1, 0)

	if not is_flying:
		movement_direction = Vector3(new_move_dir.x, 0.0, new_move_dir.z).normalized()
	else:
		movement_direction = new_move_dir.normalized()
	determine_player_move_speed()

	if not is_flying:
		# Charge up jump
		if Input.is_action_just_pressed("jump"):
			if can_jump():
				camera.v_offset = -0.05
			else:
				air_jump()
		if Input.is_action_pressed("jump") and can_jump():
			jump_charge = min(jump_charge_time, jump_charge + delta)
			camera.fov = (
				camera_starting_fov + (jump_charge / jump_charge_time) * jump_camera_stretch
			)
		# Release charged jump
		elif Input.is_action_just_released("jump") and can_jump():
			if is_crouching:
				is_crouching = false
			var jump_force = (
				min_jump_force
				+ ((jump_charge / jump_charge_time) * (max_jump_force - min_jump_force))
			)
			jump(jump_force)
			jump_charge = 0
			camera.v_offset = 0
			camera.fov = camera_starting_fov

		# Crouch
		if Input.is_action_just_pressed("crouch"):
			is_crouching = not is_crouching


func _physics_process(delta: float) -> void:
	# Apply gravity while the controller is not on the floor and not flying
	if not is_on_floor() and not is_flying:
		velocity.y -= gravity * delta

	# Track last frame on the floor
	if is_on_floor():
		was_on_floor = true
		jump_grace_timer.stop()
	elif was_on_floor:
		was_on_floor = false
		jump_grace_timer.start()

	# Using movement_drag by default
	var drag := movement_drag

	# Use the stop_drag if there is no movement direction
	if movement_direction.is_zero_approx():
		drag = stop_drag

	if is_flying:
		move_and_collide(movement_direction * max_speed * delta)
	else:
		# Get the flat velocity -> no vertical velocity
		var flat_velocity := Vector3(velocity.x, 0.0, velocity.z)

		# Calculate the velocity and add it to the current velocity
		var velocity_to_add: Vector3 = (
			(movement_acceleration * movement_direction) - (flat_velocity * drag)
		)
		velocity += velocity_to_add
		move_and_slide()

	# For pushing rigid bodies around
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		if c.get_collider() is RigidBody3D:
			c.get_collider().apply_central_impulse(-c.get_normal() * push_force)


func _input(event: InputEvent) -> void:
	# Rotate the camera based on mouse motion
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Rotate the controller left and right based on horizontal mouse motion
		rotation_degrees.y -= event.relative.x * mouse_sensitivity.x

		# Rotate the camera up and down based on vertical mouse motion
		camera.rotation_degrees.x -= event.relative.y * mouse_sensitivity.y

		# Clamp the camera rotation between min and max look angles
		camera.rotation_degrees.x = clampf(
			camera.rotation_degrees.x, min_vertical_look_angle, max_vertical_look_angle
		)


# Determine if the player is able to jump
func can_jump() -> bool:
	#return is_on_floor()
	return not is_flying and (is_on_floor() or not jump_grace_timer.is_stopped())


# Apply the jump force to the player
func jump(jump_force: float) -> void:
	if can_jump():
		air_jumps_remaining = air_jumps
		velocity.y = jump_force


# Apply the mid-air jump force to the player
func air_jump() -> void:
	if not is_flying and not can_jump() and not is_on_floor() and air_jumps_remaining > 0:
		air_jumps_remaining -= 1
		velocity.y = air_jump_force


# Determine how if the player should be walking or sprint
func determine_player_move_speed():
	if Input.is_action_pressed("walk"):
		set_new_max_speed(walk_speed)
	elif Input.is_action_pressed("sprint"):
		set_new_max_speed(sprint_speed)
	else:
		set_new_max_speed(move_speed)


# Utility function to set a new maximum speed
func set_new_max_speed(nms: float) -> void:
	if max_speed != nms:
		max_speed = nms
		# Recalculate the movement drag
		movement_drag = movement_acceleration / max_speed
