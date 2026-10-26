# Pure D1 battle tests

```sh
GODOT_BIN=/path/to/Godot-4.7.2 godot/tests/battle/run_pure.sh
```

The launcher creates a minimal, ignored `.local/battle-pure` project with no game autoloads. It loads actual core scripts and injects source JSON definitions through the test runner. It needs no images, audio, scenes, content synchronization, or import cache. Test HOME/XDG directories and logs stay in `.local/battle-tests`, outside public artifacts.

For aggregate integration, preload `battle_suite.gd` and call `new().run(definitions)`. It returns `{passed, failed, failures, combat_stress, scope}`; the suite itself has no filesystem or Node dependency. `battle_runner.gd` is the only source-data loading adapter.

Coverage includes all 24 card definitions, 15 relics, 3 keepsakes, 9 enemies, intent cycles, boss response windows, reaction ordering, choices and invalid-command immutability, resource limits, spare rope and retries, independent RNG streams, pure previews/forecasts, JSON continuation, and a fixed command/state/event replay fixture. `golden_replay.gd` contains reviewed expected hashes and must not be regenerated merely to make a changed implementation pass.

Combat stress executes 120 isolated fights (ten seeds per authored encounter plus elite and boss). The boss fixture has the starter deck, lone glove and ring. Its watchdog detects stalls; it never forces a win or imposes a rule-engine turn limit. These are deterministic implementation checks, not full-expedition balance or evidence of human enjoyment.
