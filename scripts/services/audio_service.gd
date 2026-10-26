extends Node
## Semantic cues, six SFX voices and two crossfading music voices.
## Audio does not begin before a user gesture. Focus loss pauses playback and mutes.

signal unlocked_changed(is_unlocked: bool)

const MANIFEST_PATH: String = "res://resources/audio/manifest.json"
const AUDIO_ROOT: String = "res://resources/audio/"
const SFX_VOICE_COUNT: int = 6
const MUSIC_VOICE_COUNT: int = 2
# Source WAVs keep one documented mastering range; mix frequent gestures lower
# at playback rather than weakening the offline validation gate.
const CUE_GAIN_DB: Dictionary = {
	"sfx.ui_hover": -10.0, "sfx.ui_click": -5.0, "sfx.ui_cancel": -6.0, "sfx.ui_deny": -5.0,
	"sfx.card_hover": -9.0, "sfx.card_pick": -7.0, "sfx.draw": -10.0, "sfx.discard": -10.0,
	"sfx.shuffle": -8.0, "sfx.card_play_attack": -5.0, "sfx.card_play_guard": -4.0,
	"sfx.hit_small": -2.0, "sfx.hit_big": -1.0, "sfx.hurt": -3.0,
	"sfx.guard_gain": -3.0, "sfx.guard_block": -4.0, "sfx.guard_break": -6.0,
	"sfx.enemy_wet_sock": -5.0, "sfx.enemy_poof": -4.0,
	"sfx.end_turn": -6.0, "sfx.turn_start": -6.0, "sfx.intent_reveal": -7.0,
	"sfx.rope_creak": -7.0, "sfx.rope_pull": -6.0,
}
const AMBIENCE: Dictionary = {
	"town": ["sfx.reed", "sfx.clothesline", "sfx.reed"],
	"battle": ["sfx.reed", "sfx.bubble_pop", "sfx.reed", "sfx.bubble_pop"],
}
const AMBIENCE_INTERVALS: Array[float] = [5.7, 8.1, 6.4, 9.2]
const CUE_COOLDOWN_MS: Dictionary = {"sfx.ui_hover": 75, "sfx.card_hover": 75, "sfx.ui_deny": 140}
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
var _audio_driver: String = ""
var _physical_playback_enabled: bool = true
var _movie_capture_enabled: bool = false
var _ambience_profile: String = ""
var _ambience_remaining: float = 0.0
var _ambience_step: int = 0
var _last_cue_time: Dictionary = {}
var _last_mix: Dictionary = {}
var valid: bool = false

func _ready() -> void:
	_audio_driver = AudioServer.get_driver_name()
	# Dummy has no audible output. Starting its players can retain playback/WAV
	# references until after ObjectDB shutdown in Godot 4.7.2, even after stop().
	# Use the actual backend, not headless/display flags: real backends still play.
	_physical_playback_enabled = _audio_driver != "Dummy"
	# Movie Maker really mixes audio through Dummy into the movie file. The
	# engine feature is true for an actual --write-movie run, not a test flag.
	_movie_capture_enabled = OS.has_feature("movie")
	_ensure_bus("Music", -8.0)
	_ensure_bus("SFX", -4.0)
	_ensure_bus("UI", -4.0)
	_ensure_master_limiter()
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

func _process(delta: float) -> void:
	if _ambience_profile.is_empty() or not _unlocked or not _focused or _user_muted:
		return
	_ambience_remaining -= delta
	if _ambience_remaining > 0.0:
		return
	var cues: Array = AMBIENCE[_ambience_profile]
	# Never catch up missed sounds after a pause, or steal a foreground voice.
	_play_one_shot(str(cues[_ambience_step % cues.size()]), -22.0, 1.0, true)
	_ambience_remaining = AMBIENCE_INTERVALS[_ambience_step % AMBIENCE_INTERVALS.size()]
	_ambience_step += 1

func set_ambience(profile: String) -> bool:
	if not profile.is_empty() and not AMBIENCE.has(profile):
		return false
	if profile == _ambience_profile:
		return true
	_ambience_profile = profile
	_ambience_remaining = 2.8
	_ambience_step = 0
	return true

func cue_gain_db(id: String) -> float:
	return -12.0 if id.begins_with("voice.") else float(CUE_GAIN_DB.get(id, 0.0))

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
	return _play_one_shot(id, cue_gain_db(id))

func _play_one_shot(id: String, gain_db: float, pitch: float = 1.0, ambient: bool = false) -> bool:
	if not _unlocked or not _focused:
		return false
	var now: int = Time.get_ticks_msec()
	if not ambient and CUE_COOLDOWN_MS.has(id):
		if now - int(_last_cue_time.get(id, -10000)) < int(CUE_COOLDOWN_MS[id]):
			return false
	var stream: AudioStream = _stream(id)
	if stream == null:
		return false
	var available: int = -1
	for offset: int in range(SFX_VOICE_COUNT):
		var index: int = (_next_sfx + offset) % SFX_VOICE_COUNT
		if not _sfx_players[index].playing:
			available = index
			break
	if ambient and available < 0:
		return false
	_last_cue_time[id] = now
	_last_mix = {"id": id, "gain_db": gain_db, "pitch": pitch, "ambient": ambient}
	# A successful cue request means it was accepted and its WAV loaded, not
	# that sound was heard. Keep validation active on the non-audible backend.
	if not _physical_playback_enabled and not _movie_capture_enabled:
		return true
	var selected: int = available if available >= 0 else _next_sfx
	var player: AudioStreamPlayer = _sfx_players[selected]
	_next_sfx = (selected + 1) % SFX_VOICE_COUNT
	player.stop()
	player.bus = "UI" if id.begins_with("sfx.ui_") else "SFX"
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = gain_db
	player.play()
	return true

func play_voice(speaker: String, character_index: int) -> bool:
	var voice: String = {"char.asui": "asui", "npc.maye": "maye", "npc.mai_aunt": "mai_aunt", "npc.mai_uncle": "mai_aunt", "npc.douding": "douding", "npc.xinbo": "postman", "keepsake.ring": "mai_aunt", "keepsake.letter": "postman", "keepsake.mianmian": "mianmian", "boss.sock_snake": "sock_snake", "elite.hungry_drawer": "hungry_drawer"}.get(speaker, "")
	if voice.is_empty() or not has_cue("voice." + voice) or not _unlocked or not _focused: return false
	var pitch: float = 0.94 + float(absi(character_index * 17 + speaker.hash()) % 13) * 0.01
	return _play_one_shot("voice." + voice, cue_gain_db("voice." + voice), pitch)

func play_music(id: String, fade_seconds: float = 0.6) -> bool:
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
	if not _physical_playback_enabled and not _movie_capture_enabled:
		_music_id = id
		return true
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
	set_ambience("")
	_last_cue_time.clear()

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
	return {"sfx_voices": _sfx_players.size(), "music_voices": _music_players.size(), "unlocked": _unlocked, "focused": _focused, "music": _music_id, "pending_music": _pending_music, "cue_count": _assets.size(), "audio_driver": _audio_driver, "physical_playback_enabled": _physical_playback_enabled, "movie_capture_enabled": _movie_capture_enabled, "mixer_playback_enabled": _physical_playback_enabled or _movie_capture_enabled, "loaded_streams": _streams.size(), "ambience": _ambience_profile, "ambience_step": _ambience_step, "last_mix": _last_mix.duplicate()}

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

func _ensure_master_limiter() -> void:
	var master: int = AudioServer.get_bus_index("Master")
	for index: int in range(AudioServer.get_bus_effect_count(master)):
		if AudioServer.get_bus_effect(master, index) is AudioEffectLimiter:
			return
	var limiter: AudioEffectLimiter = AudioEffectLimiter.new()
	limiter.ceiling_db = -1.0
	limiter.threshold_db = 0.0
	AudioServer.add_bus_effect(master, limiter)

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
