class_name Player
extends CharacterBody3D

enum PlayerMoveState { WALKING, CROUCHING, FLYING }
enum PlayerMoveSpeed { SLOW_WALKING, WALKING, SPRINTING }

@export_group("Mouse")
@export var mouse_sensitivity := Vector2(0.15, 0.15)
@export_range(30.0, 90.0) var max_vertical_look_angle := 90.0
@export_range(-90.0, -30.0) var min_vertical_look_angle := -90.0

@export_group("Movement")
@export var movement_acceleration = 2.0
@export var slow_walk_speed := 2.5
@export var walk_speed := 6.5
@export var sprint_speed := 14.0

@export_subgroup("Jumping")
@export_range(0.1, 30.0) var min_jump_force := 4.5
@export_range(0.2, 50.0) var max_jump_force := 11.5
@export_range(0.2, 5.0) var jump_charge_time := 0.5
@export_range(0.0, 30.0) var jump_camera_stretch := 3.5
@export_range(0.2, 30.0) var air_jump_force := 8.5
@export var air_jumps := 1

@export_subgroup("Movement Physics")
@export var stop_drag := 0.9
@export var push_force = 5.0
@export var gravity_multiplier := 2.0

@export_group("Misc")
@export var debug_info := false

var player_movement_direction := Vector3.ZERO
var player_move_speed := PlayerMoveSpeed.WALKING
var player_move_state := PlayerMoveState.WALKING:
	set(new_player_move_state):
		match new_player_move_state:
			PlayerMoveState.CROUCHING:
				player_animation.play("crouch")
			# Stand up after crouching
			_ when player_move_state == PlayerMoveState.CROUCHING:
				player_animation.play_backwards("crouch")
		player_move_state = new_player_move_state

# How fast the player should be moving at
var player_move_speed_scalar: float:
	get:
		match player_move_speed:
			PlayerMoveSpeed.SLOW_WALKING:
				return slow_walk_speed
			PlayerMoveSpeed.SPRINTING:
				return sprint_speed
			_:
				return walk_speed

var player_movement_drag: float:
	get:
		return movement_acceleration / player_move_speed_scalar

var jump_charge := 0.0
var air_jumps_remaining := air_jumps
var can_jump: bool:
	get:
		return (
			player_move_state != PlayerMoveState.FLYING
			and (is_on_floor() or not jump_grace_timer.is_stopped())
		)
var was_on_floor := false

@onready var camera: Camera3D = $Camera3D
@onready var camera_starting_fov := camera.fov
@onready var player_animation: AnimationPlayer = $PlayerAnimation
@onready var jump_grace_timer: Timer = $JumpGraceTimer


func _ready() -> void:
	# Capture the mouse at the start of the game
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	process_player_quitting_input()
	process_player_movement_state_and_speed()
	process_player_movement_direction_input()
	process_player_jump_input(delta)


func _physics_process(delta: float) -> void:
	# Apply gravity while the player is not on the floor and not flying
	if not is_on_floor() and player_move_state != PlayerMoveState.FLYING:
		velocity += get_gravity() * gravity_multiplier * delta

	# Track last frame on the floor
	if is_on_floor():
		was_on_floor = true
		jump_grace_timer.stop()
	elif was_on_floor:
		was_on_floor = false
		jump_grace_timer.start()

	# Determine drag
	var drag := player_movement_drag
	if player_movement_direction.is_zero_approx():
		drag = stop_drag

	if player_move_state == PlayerMoveState.FLYING:
		move_and_collide(player_movement_direction * player_move_speed_scalar * delta)
	else:
		# Determine velocity -> no vertical velocity
		var walk_velocity := Vector3(velocity.x, 0.0, velocity.z)

		# Calculate the velocity and add it to the current velocity
		var velocity_to_add: Vector3 = (
			(player_movement_direction * movement_acceleration) - (walk_velocity * drag)
		)
		velocity += velocity_to_add
		move_and_slide()

	physics_push_other_bodies()


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


# Process when the player hits ESC to quit and mouse re-capture if cancelling.
func process_player_quitting_input() -> void:
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


# Determine what movement state the player is in based on input
func process_player_movement_state_and_speed() -> void:
	# Flying, crouching, or walking
	if Input.is_action_just_pressed("toggle_flight"):
		if player_move_state != PlayerMoveState.FLYING:
			player_move_state = PlayerMoveState.FLYING
			play_begin_flying_tween()
		else:
			player_move_state = PlayerMoveState.WALKING

	if Input.is_action_just_pressed("crouch") and player_move_state != PlayerMoveState.FLYING:
		if player_move_state != PlayerMoveState.CROUCHING:
			player_move_state = PlayerMoveState.CROUCHING
		else:
			player_move_state = PlayerMoveState.WALKING

	# Speed
	if Input.is_action_pressed("walk"):
		player_move_speed = PlayerMoveSpeed.SLOW_WALKING
	elif Input.is_action_pressed("sprint"):
		player_move_speed = PlayerMoveSpeed.SPRINTING
	else:
		player_move_speed = PlayerMoveSpeed.WALKING


# Process what direction the player is trying to move in
func process_player_movement_direction_input() -> void:
	# Get the movement input as a Vector2
	#   X is the left/right input
	#   Y is the forward/backward
	var input_direction := Input.get_vector(
		"move_left", "move_right", "move_forward", "move_backward"
	)

	# Calculate the movement direction, multiply with the basis
	# so that we move according to the controllers rotation
	var new_move_direction := transform.basis * Vector3(input_direction.x, 0.0, input_direction.y)

	# Apply vertical direction based on player move state
	match player_move_state:
		PlayerMoveState.FLYING when Input.is_action_pressed("fly_up"):
			new_move_direction += Vector3.UP
		PlayerMoveState.FLYING when Input.is_action_pressed("fly_down"):
			new_move_direction += Vector3.DOWN
		_:
			new_move_direction.y = 0.0

	player_movement_direction = new_move_direction.normalized()


# Process player charged and air jumping
func process_player_jump_input(delta: float) -> void:
	if player_move_state != PlayerMoveState.FLYING:
		# Charge up jump
		if Input.is_action_just_pressed("jump"):
			if can_jump:
				camera.v_offset = -0.05
			else:
				air_jump()
		if Input.is_action_pressed("jump") and can_jump:
			jump_charge = min(jump_charge_time, jump_charge + delta)
			camera.fov = (
				camera_starting_fov + (jump_charge / jump_charge_time) * jump_camera_stretch
			)
		# Release charged jump
		elif Input.is_action_just_released("jump") and can_jump:
			if player_move_state == PlayerMoveState.CROUCHING:
				player_move_state = PlayerMoveState.WALKING
			var jump_force = (
				min_jump_force
				+ ((jump_charge / jump_charge_time) * (max_jump_force - min_jump_force))
			)
			jump(jump_force)
			jump_charge = 0
			camera.v_offset = 0
			camera.fov = camera_starting_fov


# Determine the drag to apply to player movement
func physics_calculate_drag() -> float:
	var drag := player_movement_drag
	if player_movement_direction.is_zero_approx():
		drag = stop_drag
	return drag


# Push other physics bodies
func physics_push_other_bodies() -> void:
	for i in get_slide_collision_count():
		var c = get_slide_collision(i)
		if c.get_collider() is RigidBody3D:
			c.get_collider().apply_central_impulse(-c.get_normal() * push_force)


# Apply the jump force to the player
func jump(jump_force: float) -> void:
	if can_jump:
		air_jumps_remaining = air_jumps
		velocity.y = jump_force


# Apply the mid-air jump force to the player
func air_jump() -> void:
	if (
		player_move_state != PlayerMoveState.FLYING
		and not can_jump
		and not is_on_floor()
		and air_jumps_remaining > 0
	):
		air_jumps_remaining -= 1
		velocity.y = air_jump_force


# Lift player into the air when they start flying
func play_begin_flying_tween() -> void:
	var flight_tween := create_tween()
	flight_tween.set_ease(Tween.EASE_OUT)
	flight_tween.set_trans(Tween.TRANS_QUAD)
	flight_tween.tween_property(self, "global_position", global_position + Vector3(0, 3.5, 0), 0.3)
	flight_tween.play()
