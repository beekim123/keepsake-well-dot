class_name WellRng
extends RefCounted
## Portable xorshift32. JSON snapshots and named streams never share state.
var seed: int = 1
var state: int = 1
var draws: int = 0

func _init(value: Variant = 1) -> void:
	if value is Dictionary:
		seed = int(value.get("seed", 1)) & 0xffffffff
		state = int(value.get("state", seed)) & 0xffffffff
		draws = int(value.get("draws", 0))
	else:
		seed = int(value) & 0xffffffff
		state = seed
	if state == 0:
		state = 0x6d2b79f5

static func derive(value: int, stream: String) -> int:
	var result: int = (value ^ 2166136261) & 0xffffffff
	for byte: int in stream.to_utf8_buffer():
		result = ((result ^ byte) * 16777619) & 0xffffffff
	return result if result != 0 else 1

func next_u32() -> int:
	state = (state ^ (state << 13)) & 0xffffffff
	state = (state ^ (state >> 17)) & 0xffffffff
	state = (state ^ (state << 5)) & 0xffffffff
	draws += 1
	return state

func range_int(minimum: int, maximum: int) -> int:
	if maximum <= minimum:
		return minimum
	var width: int = maximum - minimum + 1
	var limit: int = 4294967296 - (4294967296 % width)
	var value: int = next_u32()
	while value >= limit:
		value = next_u32()
	return minimum + value % width

func shuffle(values: Array) -> Array:
	for index: int in range(values.size() - 1, 0, -1):
		var other: int = range_int(0, index)
		var temporary: Variant = values[index]
		values[index] = values[other]
		values[other] = temporary
	return values

func snapshot() -> Dictionary:
	return {"seed": seed, "state": state, "draws": draws}
