# Skyloop

A property-trading board game for Android, built in Godot 4.7: a floating sky-island city,
12-round matches, sealed auctions, takeovers, headlines and tycoons.

- `core/` — deterministic rules engine (`game.gd`), board data and tuning (`board.gd`), bots.
- `game3d/` — 3D board, procedural models, shaders.
- `ui/` — HUD, menu, sound/haptics autoload.
- `tools/` — balance simulator and test runner (run headless).
- `docs/` — rules (`DESIGN.md`) and art prompts.

```
godot --headless --path . --script res://tools/sim.gd -- --games 3000
godot --headless --path . --script res://tools/test.gd
```
