extends SceneTree
## Deliberately quits in the same frame as accepted music/SFX: no mixer-delay
## workaround and no manual stop on the immediate-exit case. The launcher checks
## the entire process output, including diagnostics printed after this report.

const AudioSuite = preload("res://tests/audio/audio_suite.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var result: Dictionary = AudioSuite.new().run_suite(self)
	var audio: Node = root.get_node("AudioService")
	var stopped: bool = OS.get_cmdline_user_args().has("--stop-before-exit")
	var accepted: bool = audio.play_music("music.title")
	audio.unlock()
	accepted = audio.play("sfx.ui_click") and accepted
	accepted = audio.play("sfx.card_play_attack") and accepted
	var diagnostics: Dictionary = audio.diagnostics()
	if not accepted or diagnostics.get("loaded_streams", 0) != 3 or diagnostics["music"] != "music.title":
		result["failed"] += 1
		printerr("FAIL audio: exit probe did not load/accept all current cues")
	if AudioServer.get_driver_name() != "Dummy":
		result["failed"] += 1
		printerr("FAIL audio: process regression must use actual Dummy backend")
	if stopped:
		audio.stop_all()
	print("AUDIO_TEST_RESULT: " + JSON.stringify({"format": "audio-shutdown-tests/1", "passed": result["passed"], "failed": result["failed"], "case": "stopped" if stopped else "immediate", "audio_driver": AudioServer.get_driver_name(), "physical_playback_enabled": diagnostics.get("physical_playback_enabled", null), "loaded_streams": diagnostics.get("loaded_streams", 0), "listening_verified": false}))
	quit(0 if result["failed"] == 0 else 1)
