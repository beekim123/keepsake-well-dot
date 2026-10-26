# Audio shutdown regression

```sh
GODOT_BIN=/path/to/godot-4.7.2 node godot/tests/audio/run.mjs
```

The launcher verifies the exact engine version using isolated `HOME`/XDG paths,
copies the current audio service and actual synchronized WAV resources to a fresh
ignored `.local/audio-shutdown-*` project, and imports them with Godot. It runs two
actual Dummy-backend processes: immediate exit after music/SFX requests, and
explicit `stop_all()` before exit. Both must complete the functional suite and
exit without engine/script errors, ObjectDB/resource/RID leaks, or orphan names.
Logs remain in that private directory for diagnosis. No native window is opened.

`audio_suite.gd` also runs inside the aggregate Godot tests. It owns a fresh
service so foundation lock/unlock assertions remain independent. It checks
gesture gating, loaded WAV contents and metadata, loops, semantic music changes,
focus/mute, bus volume, stop/restart, and actual-backend diagnostics. Only Dummy
skips physical playback; other backends retain the service's players/crossfade.

This regression deliberately does not add a mixer-delay workaround. Success means
the actual cue assets loaded and shutdown is clean, **not that audio was heard**.
Keep `npm run audio:check` and the Node audio-pipeline tests: source PCM bytes,
determinism, loudness and loop-seam checks are separate from engine lifetime QA.
