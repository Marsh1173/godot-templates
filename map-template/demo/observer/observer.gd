extends CharacterBody3D

@onready var camera_pivot = $CameraPivot

const _move_speed = 5
const _forward_move_speed = 5
var _accumulated_extra_move_speed = 1

var _space_pressed: bool = false
var _shift_pressed: bool = false
var _w_pressed: bool = false
var _a_pressed: bool = false
var _s_pressed: bool = false
var _d_pressed: bool = false

const _look_sensitivity = 0.0025
var _look_rotation = Vector2(0.0, PI * 5 / 4)

func _input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			#DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	elif event is InputEventKey:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			#DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		if event.keycode == KEY_SPACE:
			_space_pressed = event.pressed
		elif event.keycode == KEY_E:
			_accumulated_extra_move_speed *= 1.5
		elif event.keycode == KEY_Q:
			_accumulated_extra_move_speed /= 1.5
		elif event.keycode == KEY_SHIFT:
			_shift_pressed = event.pressed
		elif event.keycode == KEY_W:
			_w_pressed = event.pressed
		elif event.keycode == KEY_A:
			_a_pressed = event.pressed
		elif event.keycode == KEY_S:
			_s_pressed = event.pressed
		elif event.keycode == KEY_D:
			_d_pressed = event.pressed
	elif event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_look_rotation.y -= event.relative.x * _look_sensitivity
			_look_rotation.x = clamp(-PI / 2, _look_rotation.x - (event.relative.y * _look_sensitivity), PI / 2)
		

func _process(_delta):
	camera_pivot.rotation.y = _look_rotation.y
	camera_pivot.rotation.x = _look_rotation.x
	
	var move_vector = Vector3(0, 0, 0)
	
	if _space_pressed:
		move_vector.y += _move_speed
	if _shift_pressed:
		move_vector.y -= _move_speed
	
	if _w_pressed:
		move_vector.z -= _forward_move_speed
	if _s_pressed:
		move_vector.z += _forward_move_speed
	
	if _d_pressed:
		move_vector.x += _move_speed
	if _a_pressed:
		move_vector.x -= _move_speed
	
	var rotated_move_vector = move_vector.rotated(Vector3.UP, _look_rotation.y)
	
	velocity.x =  rotated_move_vector.x * _accumulated_extra_move_speed
	velocity.y =  rotated_move_vector.y * _accumulated_extra_move_speed
	velocity.z =  rotated_move_vector.z * _accumulated_extra_move_speed
	move_and_slide()
