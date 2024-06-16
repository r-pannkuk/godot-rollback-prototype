extends SGFixedNode2D

@export var explosion_scene : PackedScene

@onready var explosion_timer : NetworkTimer = $ExplosionTimer
@onready var animation_player : NetworkAnimationPlayer = $AnimationPlayer

func _ready():
	explosion_timer.timeout.connect(_on_timer_timeout)

func _network_spawn(data: Dictionary) -> void:
	set_global_fixed_position(data['position'].copy())
	animation_player.play("tick")
	explosion_timer.start()

func _on_timer_timeout():
	SyncManager.spawn("Explosion", get_parent(), explosion_scene, {'position': get_global_fixed_position().copy()})
	SyncManager.despawn(self)
