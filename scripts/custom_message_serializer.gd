extends "res://addons/godot-rollback-netcode/MessageSerializer.gd"

const INPUT_PATH_PREFIX : String = '/root/Main/Players/'

var INPUT_PATH_MAP = {}

var INPUT_PATH_MAP_REVERSED = {}

enum HeaderFlags {
	HAS_INPUT_VECTOR = 1 << 0,
	DROP_BOMB = 1 << 1,
	TELEPORT = 1 << 2,
}

# # Packet Shape:
# # 32 bits - Input Hash 
# # 8  bits - Size of Nodes
# # For each Node:
# 	# 8 bits - Path of Node
# 	# 8 bits - HeaderFlags
# 	# ? bits - Input Data

func _init() -> void:
	for i in range(Main.MAX_CLIENTS + 1):
		INPUT_PATH_MAP[INPUT_PATH_PREFIX + str(i + 1)] = i + 1
	for path in INPUT_PATH_MAP:
		INPUT_PATH_MAP_REVERSED[INPUT_PATH_MAP[path]] = path

func serialize_input(all_input: Dictionary) -> PackedByteArray:
	var buffer : StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.resize(16)

	buffer.put_u32(all_input['$'])

	buffer.put_u8(all_input.size() - 1)

	for path : String in all_input:
		if path == '$':
			continue

		buffer.put_u8(INPUT_PATH_MAP[path])

		var header : int = 0

		var input = all_input[path]
		if input.has('input_vector'):
			header |= HeaderFlags.HAS_INPUT_VECTOR
		if input.get('drop_bomb', false):
			header |= HeaderFlags.DROP_BOMB
		if input.get('teleport', false):
			header |= HeaderFlags.TELEPORT

		buffer.put_u8(header)

		if input.has('input_vector'):
			var input_vector : SGFixedVector2 = input['input_vector']
			buffer.put_u64(input_vector.x)
			buffer.put_u64(input_vector.y)

	buffer.resize(buffer.get_position())
	return buffer.data_array

func unserialize_input(serialized: PackedByteArray) -> Dictionary:
	var buffer = StreamPeerBuffer.new()
	buffer.put_data(serialized)
	buffer.seek(0)

	var all_input : Dictionary = {}

	all_input['$'] = buffer.get_u32()
	var size = buffer.get_u8()

	for i in range(size):
		var path = buffer.get_u8()
		var header = buffer.get_u8()

		var input : Dictionary = {}
		if header & HeaderFlags.HAS_INPUT_VECTOR:
			var input_vector : SGFixedVector2= SGFixedVector2.new() 
			input_vector.x = buffer.get_u64()
			input_vector.y = buffer.get_u64()
			input['input_vector'] = input_vector
		if header & HeaderFlags.DROP_BOMB:
			input["drop_bomb"] = true
		if header & HeaderFlags.TELEPORT:
			input["teleport"] = true

		all_input[INPUT_PATH_MAP_REVERSED[path]] = input

	return all_input
