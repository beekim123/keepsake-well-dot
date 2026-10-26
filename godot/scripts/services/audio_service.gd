extends Node
## D0 audio: semantic cue IDs, six SFX voices, two crossfading music voices.
## Audio does not begin before a user gesture. Focus loss pauses playback and mutes.

signal unlocked_changed(is_unlocked: bool)

const MANIFEST_PATH: String = "res://resources/audio/manifest.json"
const AUDIO_ROOT: String = "res://resources/audio/"
const SFX_VOICE_COUNT: int = 6
const MUSIC_VOICE_COUNT: int = 2
var _assets: Dictionary = {}
var _streams: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _music_players: Array[AudioStreamPlayer] = []
var _next_sfx: int = 0
var _music_slot: int = 0
var _music_id: String = ""
var _pending_music: String = ""
var _crossfade: Tween
var _unlocked: bool = false
var _focused: bool = true
var _user_muted: bool = false
var valid: bool = false

func _ready() -> void:
	_ensure_bus("Music", -8.0)
	_ensure_bus("SFX", -4.0)
	_ensure_bus("UI", -4.0)
	for index: int in range(SFX_VOICE_COUNT):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "SFXVoice%d" % index
		player.bus = "SFX"
		add_child(player)
		_sfx_players.append(player)
	for index: int in range(MUSIC_VOICE_COUNT):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "MusicVoice%d" % index
		player.bus = "Music"
		add_child(player)
		_music_players.append(player)
	valid = _load_manifest()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		unlock()
	elif event is InputEventKey and event.pressed and not event.echo:
		unlock()
	elif event is InputEventScreenTouch and event.pressed:
		unlock()

func unlock() -> void:
	if _unlocked:
		return
	_unlocked = true
	unlocked_changed.emit(true)
	if not _pending_music.is_empty():
		var pending: String = _pending_music
		_pending_music = ""
		play_music(pending)

func is_unlocked() -> bool:
	return _unlocked

func play(id: String) -> bool:
	if id.begins_with("music."):
		return play_music(id)
	if not _unlocked or not _focused:
		return false
	var stream: AudioStream = _stream(id)
	if stream == null:
		return false
	var player: AudioStreamPlayer = _sfx_players[_next_sfx]
	_next_sfx = (_next_sfx + 1) % SFX_VOICE_COUNT
	player.stop()
	player.bus = "UI" if id.begins_with("sfx.ui_") else "SFX"
	player.stream = stream
	player.play()
	return true

func play_music(id: String, fade_seconds: float = 0.35) -> bool:
	if not _assets.has(id):
		push_error("AudioService: unknown music cue " + id)
		return false
	if not _unlocked:
		_pending_music = id
		return true
	if id == _music_id:
		return true
	var stream: AudioStream = _stream(id)
	if stream == null:
		return false
	if _crossfade != null and _crossfade.is_valid():
		_crossfade.kill()
	var previous: AudioStreamPlayer = _music_players[_music_slot]
	_music_slot = (_music_slot + 1) % MUSIC_VOICE_COUNT
	var next: AudioStreamPlayer = _music_players[_music_slot]
	next.stop()
	next.stream = stream
	next.volume_db = -60.0
	next.play()
	next.stream_paused = not _focused
	_music_id = id
	_crossfade = create_tween().set_parallel(true)
	_crossfade.tween_property(next, "volume_db", 0.0, maxf(fade_seconds, 0.001))
	_crossfade.tween_property(previous, "volume_db", -60.0, maxf(fade_seconds, 0.001))
	_crossfade.chain().tween_callback(previous.stop)
	return true

func stop_all() -> void:
	if _crossfade != null and _crossfade.is_valid():
		_crossfade.kill()
	for player: AudioStreamPlayer in _sfx_players:
		player.stop()
		player.stream = null
	for player: AudioStreamPlayer in _music_players:
		player.stop()
		player.stream = null
	_music_id = ""
	_pending_music = ""

func _exit_tree() -> void:
	stop_all()

func set_bus_volume(bus: String, linear_volume: float) -> bool:
	var index: int = AudioServer.get_bus_index(bus)
	if index < 0:
		return false
	AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear_volume, 0.0, 1.0)))
	return true

func set_muted(muted: bool) -> void:
	_user_muted = muted
	_update_master_mute()

func set_focused(focused: bool) -> void:
	_focused = focused
	for player: AudioStreamPlayer in _sfx_players:
		player.stream_paused = not focused
	for player: AudioStreamPlayer in _music_players:
		player.stream_paused = not focused
	_update_master_mute()

func diagnostics() -> Dictionary:
	return {"sfx_voices": _sfx_players.size(), "music_voices": _music_players.size(), "unlocked": _unlocked, "focused": _focused, "music": _music_id, "pending_music": _pending_music, "cue_count": _assets.size()}

func has_cue(id: String) -> bool:
	return _assets.has(id)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		set_focused(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		set_focused(true)

func _update_master_mute() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), _user_muted or not _focused)

func _ensure_bus(bus: String, volume_db: float) -> void:
	var index: int = AudioServer.get_bus_index(bus)
	if index == -1:
		AudioServer.add_bus()
		index = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, "Master")
	AudioServer.set_bus_volume_db(index, volume_db)

func _load_manifest() -> bool:
	var file: FileAccess = FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_error("AudioService: audio manifest is missing; run sync")
		return false
	var parser: JSON = JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		push_error("AudioService: invalid audio manifest JSON")
		return false
	var manifest: Dictionary = parser.data
	if manifest.get("format", "") != "audio-manifest/1":
		push_error("AudioService: unsupported audio manifest")
		return false
	for item: Dictionary in manifest.get("assets", []):
		var id: String = str(item.get("id", ""))
		var relative: String = str(item.get("file", ""))
		if id.is_empty() or _assets.has(id) or relative.is_empty() or relative.contains("..") or relative.is_absolute_path():
			push_error("AudioService: invalid or duplicate cue " + id)
			return false
		_assets[id] = item
	return true

func _stream(id: String) -> AudioStream:
	if _streams.has(id):
		return _streams[id] as AudioStream
	if not _assets.has(id):
		push_error("AudioService: unknown cue " + id)
		return null
	var stream: AudioStreamWAV = load(AUDIO_ROOT + str(_assets[id]["file"])) as AudioStreamWAV
	if stream == null:
		push_error("AudioService: WAV unavailable " + id)
		return null
	stream = stream.duplicate() as AudioStreamWAV
	if bool(_assets[id].get("loop", false)):
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(_assets[id]["frames"])
	_streams[id] = stream
	return stream
