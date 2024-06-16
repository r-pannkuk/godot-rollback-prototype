extends SGCharacterBody2D

@export var player_id : int = 1
@export var max_speed : int = 10
@export var bomb_scene : PackedScene

@onready var rng : NetworkRandomNumberGenerator = $NetworkRandomNumberGenerator

var speed : int = 0
var is_teleporting: bool = false

const MOVEMENT_SPEED := 65536*4

var input_actions : Dictionary : 
	get:
		return {
			"up": "up_player%s" % player_id,
			"down": "down_player%s" % player_id,
			"left": "left_player%s" % player_id,
			"right": "right_player%s" % player_id,
			"bomb": "bomb_player%s" % player_id,
			"teleport" : "teleport_player%s" % player_id,
		}

@onready var PHYSICS_REFRESH_RATE = ProjectSettings.get_setting("physics/common/physics_ticks_per_second")

func _get_local_input() -> Dictionary:
	var input_vector = SGFixedVector2.new()
	input_vector.from_float(Input.get_vector(
		input_actions.left,
		input_actions.right,
		input_actions.up,
		input_actions.down,
	).normalized())

	var input : Dictionary = {}
	input["input_vector"] = input_vector.copy()

	if Input.is_action_just_pressed(input_actions.bomb):
		input["drop_bomb"] = true

	if Input.is_action_just_pressed(input_actions.teleport):
		input["teleport"] = true
	
	return input

func _predict_remote_input(previous_input: Dictionary, ticks_since_last_input: int) -> Dictionary:
	var input = previous_input.duplicate()
	input.erase('drop_bomb')

	if ticks_since_last_input > 2:
		input.erase('input_vector')

	return input

func teleport():
	var new_position = SGFixedVector2.new()
	new_position.x = SGFixed.from_int(rng.randi() % 1152)
	new_position.y = SGFixed.from_int(rng.randi() % 648)
	set_global_fixed_position(new_position)

	sync_to_physics_engine()

func _network_process(input: Dictionary) -> void:
	velocity = input.get("input_vector", SGFixedVector2.new())
	if velocity.x != 0 or velocity.y != 0:
		if speed < max_speed:
			speed += max_speed / (5 * PHYSICS_REFRESH_RATE / 60)
	else:
		if speed > 0:
			speed -= max_speed / (5 * PHYSICS_REFRESH_RATE / 60)

	if speed > 0:
		velocity.imul(SGFixed.from_int(speed))
	else:
		velocity = SGFixedVector2.new()

	if input.get("teleport", false):
		is_teleporting = true
		teleport()
	else:
		is_teleporting = false

	move_and_slide()

	if input.get("drop_bomb", false):
		SyncManager.spawn("Bomb", get_parent(), bomb_scene, {"position": get_global_fixed_position()})


func _save_state() -> Dictionary:
	return {
		"position" : get_global_fixed_position(),
		"velocity": velocity.copy(),
		"is_teleporting": is_teleporting,
	}

func _load_state(state: Dictionary) -> void:
	if state.has("position"):
		set_global_fixed_position(state["position"].copy())
	if state.has("velocity"):
		velocity = state["velocity"].copy()
	if state.has("is_teleporting"):
		is_teleporting = state["is_teleporting"]
	
	sync_to_physics_engine()

func _interpolate_state(old_state: Dictionary, new_state: Dictionary, weight: float) -> void:
	if old_state.get("is_teleporting", false) or new_state.get("is_teleporting", false):
		return
	set_global_fixed_position(old_state['position'].linear_interpolate(new_state['position'], int(weight * 65536)))