class_name Main
extends Node2D

const MAX_CLIENTS = 2
const LOG_DIRECTORY = "user://detailed_logs/"
const DUMMY_NETWORK_ADAPTOR = preload("res://addons/godot-rollback-netcode/DummyNetworkAdaptor.gd")

@export var logging_enabled : bool = true

@onready var main_menu = $CanvasLayer/MainMenu
@onready var connection_panel = $CanvasLayer/ConnectionPanel
@onready var host_field = %HostField
@onready var port_field = %PortField
@onready var message_label = $CanvasLayer/MessageLabel
@onready var sync_lost_label = $CanvasLayer/SyncLostLabel
@onready var player_spawn_node : Node2D = $Players

var player_scene = preload("res://scenes/player.tscn")
var game_started : bool = false
var dedicated_server : bool = false

var player_ids : Dictionary = {}

func output(msg: String):
	print(msg)
	message_label.text = msg

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	SyncManager.sync_started.connect(_on_sync_started)
	SyncManager.sync_stopped.connect(_on_sync_stopped)
	SyncManager.sync_lost.connect(_on_sync_lost)
	SyncManager.sync_regained.connect(_on_sync_regained)
	SyncManager.sync_error.connect(_on_sync_error)

	if OS.has_feature("dedicated_server"):
		dedicated_server = true
		output("Starting dedicated server...")
		_host()


func _host():
	var peer = ENetMultiplayerPeer.new()
	var port = int(port_field.text if port_field.text != null and port_field.text != "" else port_field.placeholder_text)
	var result = peer.create_server(port, MAX_CLIENTS)
	GlobalRNG.randomize()
	if result != OK:
		output("Failed to host")
		return
	multiplayer.multiplayer_peer = peer
	connection_panel.visible = false
	main_menu.visible = false
	output("Listening on port %s..." % port)

func _on_join_button_pressed():
	var peer = ENetMultiplayerPeer.new()
	var host = host_field.text if host_field.text != null and host_field.text != "" else host_field.placeholder_text
	var port = int(port_field.text if port_field.text != null and port_field.text != "" else port_field.placeholder_text)
	var result = peer.create_client(host, port)
	if result != OK:
		output("Failed to connect")
		return
	multiplayer.multiplayer_peer = peer
	connection_panel.visible = false
	main_menu.visible = false
	output("Connecting to %s:%s..." % [host, port])

func _spawn_player(peer_id: int, new_name: String, location: SGFixedVector2) -> Node2D:
	var player_to_add = player_scene.instantiate()
	player_to_add.set_multiplayer_authority(peer_id)

	if peer_id == SyncManager.network_adaptor.get_unique_id():
		if peer_id == 1:
			player_to_add.get_node("CharacterSprite").modulate = Color(1, 0, 0, 1)
		else:
			player_to_add.get_node("CharacterSprite").modulate = Color(0, 0, 1, 1)
	
	print("Spawning player for peer %s while my unique_id is %s (Host: %s)" % [
		peer_id, 
		SyncManager.network_adaptor.get_unique_id(), 
		SyncManager.network_adaptor.is_network_host()
	])
	
	player_to_add.name = new_name

	player_spawn_node.add_child(player_to_add)

	player_to_add.fixed_position = location

	return player_to_add

func _spawn_all_players():
	var to_spawn = player_ids.duplicate()
	to_spawn.erase(1)

	for child in player_spawn_node.get_children():
		if str(child.get_multiplayer_authority()) in player_ids:
			to_spawn.erase(str(child.get_multiplayer_authority()))

	print("(%s) Spawning: %s" % [SyncManager.network_adaptor.get_unique_id(), to_spawn])

	var starting_index = len(player_spawn_node.get_children())

	var values = to_spawn.values()
	values.sort()

	for i in len(values):
		var new_position = SGFixedVector2.new()
		new_position.x = -300 + i * 100
		new_position.y = 0
		_spawn_player(values[i], str(starting_index + i + 1), new_position)

	for child in player_spawn_node.get_children():
		print("Node %s owned by %s" % [child.name, child.get_multiplayer_authority()])

@rpc("any_peer", "call_local")
func setup_match(data: Dictionary) -> void:
	GlobalRNG.set_seed(data.global_seed)

	print("I'm %s and my seed is: %s" % [SyncManager.network_adaptor.get_unique_id(), GlobalRNG.get_seed()])


func _start_game():
	output("Starting...")
	rpc("setup_match", {global_seed = GlobalRNG.get_seed()})
	await get_tree().create_timer(2.0).timeout
	SyncManager.start()
	game_started = true

func _on_peer_connected(id: int):
	output("Peer %s Connected!" % id)
	SyncManager.add_peer(id)

	player_ids[id] = id
	player_ids[SyncManager.network_adaptor.get_unique_id()] = SyncManager.network_adaptor.get_unique_id()

	if SyncManager.network_adaptor.is_network_host() and not game_started:
		_start_game()
	elif game_started:
		_spawn_all_players()
	pass

func _on_peer_disconnected(id: int):
	output("Peer %s Disconnected" % id)
	SyncManager.remove_peer(id)
	pass

func _on_server_disconnected():
	_on_peer_disconnected(1)
	pass

func _on_reset_pressed():
	SyncManager.stop()
	SyncManager.clear_peers()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	get_tree().reload_current_scene()

func _write_logs():
	if not DirAccess.dir_exists_absolute(LOG_DIRECTORY):
		DirAccess.make_dir_absolute(LOG_DIRECTORY)
	
	var datetime = Time.get_datetime_dict_from_system(true)
	var log_file_name = "%04d%02d%02d-%02d%02d%02d-peer-%d.log" % [
		datetime.year,
		datetime.month,
		datetime.day,
		datetime.hour,
		datetime.minute,
		datetime.second,
		SyncManager.network_adaptor.get_unique_id()
	]

	SyncManager.start_logging(LOG_DIRECTORY + log_file_name)


func _on_sync_started():
	output("Started!")

	if logging_enabled and not SyncReplay.active:
		_write_logs()

	_spawn_all_players()

	for child in player_spawn_node.get_children():
		child.rng.set_seed(GlobalRNG.randi())

	pass

func _on_sync_stopped():
	pass

func _on_sync_lost():
	sync_lost_label.visible = true
	pass

func _on_sync_regained():
	sync_lost_label.visible = false
	pass

func _on_sync_error(msg: String):
	message_label.text = msg
	sync_lost_label.visible = false

	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	SyncManager.clear_peers()

	get_tree().reload_current_scene()

func _on_online_pressed():
	connection_panel.popup_centered()
	SyncManager.reset_network_adaptor()

func _on_offline_pressed():
	main_menu.visible = false
	SyncManager.network_adaptor = DUMMY_NETWORK_ADAPTOR.new()
	player_ids["Player1"] = 1
	# Giving it server authority still even if player id 2 for offline play
	player_ids["Player2"] = 1
	SyncManager.start()

	await SyncManager.sync_started

	player_spawn_node.get_node("2").player_id = 2


func _on_connection_panel_close_requested():
	connection_panel.visible = false