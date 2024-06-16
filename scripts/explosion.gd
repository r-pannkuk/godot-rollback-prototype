extends SGFixedNode2D

@onready var animation_player : NetworkAnimationPlayer = $AnimationPlayer
@export var sound : Resource = preload("res://assets/explosion.wav")

func _ready():
	animation_player.animation_finished.connect(_on_timer_timeout.unbind(1))

func _network_spawn(data: Dictionary) -> void:
	set_global_fixed_position(data['position'].copy())
	animation_player.play("explode")
	SyncManager.play_sound(str(get_path()) + ":explosion", sound)

func _on_timer_timeout():
	SyncManager.despawn(self)
