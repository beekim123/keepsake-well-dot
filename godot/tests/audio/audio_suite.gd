extends RefCounted
## A fresh service keeps this suite independent of the foundation suite's unlock.
## Dummy assertions prove cue loading/state, never audible playback or listening.

const AudioServiceScript = preload("res://scripts/services/audio_service.gd")
var _passed: int = 0
var _failed: int = 0
var _unlock_events: int = 0

func run_suite(tree: SceneTree) -> Dictionary:
	_passed = 0
	_failed = 0
	_unlock_events = 0
	var master: int = AudioServer.get_bus_index("Master")
	var previous_mute: bool = AudioServer.is_bus_mute(master)
	var previous_music_volume: float = AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))
	var audio: Node = AudioServiceScript.new()
	tree.root.add_child(audio)
	audio.unlocked_changed.connect(_on_unlocked)
	var initial: Dictionary = audio.diagnostics()
	var dummy: bool = AudioServer.get_driver_name() == "Dummy"
	_check(audio.valid, "manifest loads in a fresh audio service")
	_check(initial.get("audio_driver", "") == AudioServer.get_driver_name(), "diagnostics report the actual audio backend")
	_check(initial.get("physical_playback_enabled", null) == not dummy, "only the actual Dummy backend disables physical playback")
	_check(initial["sfx_voices"] == 6 and initial["music_voices"] == 2, "six SFX and two music voices remain allocated")
	_check(not audio.is_unlocked() and initial.get("loaded_streams", -1) == 0, "initially locked without loaded streams")
	_check(not audio.play("sfx.ui_click"), "locked service rejects SFX")
	_check(audio.play_music("music.title") and audio.diagnostics()["pending_music"] == "music.title", "locked music queues by semantic ID")
	var key: InputEventKey = InputEventKey.new()
	key.pressed = true
	key.echo = true
	audio._input(key)
	_check(not audio.is_unlocked(), "key repeats do not unlock audio")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.pressed = false
	audio._input(click)
	_check(not audio.is_unlocked(), "mouse release does not unlock audio")
	click.pressed = true
	audio._input(click)
	audio.unlock()
	_check(audio.is_unlocked() and _unlock_events == 1, "first pressed gesture unlocks exactly once")
	_check(audio.diagnostics()["music"] == "music.title" and audio.diagnostics()["pending_music"] == "", "unlock consumes queued music")
	_check(audio.diagnostics().get("loaded_streams", -1) == 1, "queued music loads its actual WAV even on Dummy")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/audio/manifest.json"))
	for asset: Dictionary in manifest["assets"]:
		var id: String = str(asset["id"])
		_check(audio.play(id), "accepted registered cue " + id)
		var loaded: Dictionary = audio.get("_streams")
		var stream: AudioStreamWAV = loaded.get(id) as AudioStreamWAV
		_check(stream != null and stream.data.size() > 0, "cue loads nonempty imported WAV data " + id)
		if stream != null:
			_check(stream.format == AudioStreamWAV.FORMAT_16_BITS, "imported WAV remains uncompressed PCM16 " + id)
			_check(stream.data.size() == int(asset["frames"]) * 2, "PCM16 sample bytes preserve every mono frame " + id)
			_check(absf(stream.get_length() - float(asset["duration"])) < 0.001, "loaded WAV duration matches manifest " + id)
			_check(stream.mix_rate == int(asset["sampleRate"]) and not stream.stereo, "loaded WAV rate and channel count match " + id)
			if bool(asset.get("loop", false)):
				_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == 0 and stream.loop_end == int(asset["frames"]), "music retains full forward loop " + id)
			else:
				_check(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "SFX remains non-looping " + id)
	_check(audio.diagnostics().get("loaded_streams", -1) == manifest["assets"].size(), "all registered cues loaded, not silently skipped on Dummy")
	var streams_before: int = int(audio.diagnostics().get("loaded_streams", -1))
	_check(audio.play_music("music.title") and audio.diagnostics().get("loaded_streams", -1) == streams_before, "repeating music retains semantic state and stream cache")
	# A test-only second ID reuses the real WAV to exercise a music transition;
	# it does not pretend that an additional composed cue exists in the pack.
	var assets: Dictionary = audio.get("_assets")
	assets["music.audio_regression"] = assets["music.title"].duplicate(true)
	_check(audio.play_music("music.audio_regression", 0.02), "music can transition to another semantic cue")
	_check(audio.diagnostics()["music"] == "music.audio_regression", "music transition updates requested cue")
	if dummy:
		_check(audio.get("_crossfade") == null, "Dummy does not create a physical music crossfade")
		for child: Node in audio.get_children():
			var player: AudioStreamPlayer = child as AudioStreamPlayer
			_check(player != null and not player.playing and player.stream == null, "Dummy creates no playback or player stream reference " + child.name)
	else:
		_check(audio.get("_crossfade") != null, "real backend retains music crossfade")
	audio.set_muted(false)
	audio.set_focused(false)
	_check(AudioServer.is_bus_mute(master) and not audio.play("sfx.ui_click"), "focus loss mutes and rejects new SFX")
	_check(audio.play_music("music.title"), "music cue can change while unfocused")
	for child: Node in audio.get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		if dummy:
			_check(not player.playing and player.stream == null, "focus changes create no Dummy playback " + child.name)
		elif player.has_stream_playback():
			_check(player.stream_paused, "focus loss pauses active voice " + child.name)
	audio.set_focused(true)
	_check(not AudioServer.is_bus_mute(master), "focus return restores unmuted preference")
	audio.set_muted(true)
	audio.set_focused(false)
	audio.set_focused(true)
	_check(AudioServer.is_bus_mute(master), "focus return preserves explicit mute")
	audio.set_muted(false)
	_check(audio.set_bus_volume("Music", 0.5) and is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Music")), 0.5), "bus volume control still applies")
	_check(not audio.set_bus_volume("AudioRegressionMissingBus", 0.5), "missing volume bus is rejected")
	audio.stop_all()
	_check(audio.diagnostics()["music"] == "" and audio.diagnostics()["pending_music"] == "", "stop clears active and queued music IDs")
	for child: Node in audio.get_children():
		var player: AudioStreamPlayer = child as AudioStreamPlayer
		_check(not player.playing and player.stream == null, "stop releases player stream " + child.name)
	_check(audio.play_music("music.title") and audio.play("sfx.ui_click"), "cues are accepted again after stop")
	audio.free()
	AudioServer.set_bus_mute(master, previous_mute)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), previous_music_volume)
	return {"passed": _passed, "failed": _failed}

func _on_unlocked(is_unlocked: bool) -> void:
	if is_unlocked:
		_unlock_events += 1

func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("PASS audio: " + label)
	else:
		_failed += 1
		printerr("FAIL audio: " + label)
