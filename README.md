# Skyloop

A 4-player property board game for Android, built in Godot 4.7: a floating sky-island city,
8-round matches, sealed auctions, takeovers, headlines, tycoon powers, and online tables with
localized city names.

- `core/`: the deterministic rules engine (`game.gd`), board data and tuning (`board.gd`), bots,
  and the economy (`economy.gd`: tables, rewards, shop).
- `net/`: the game service. `backend.gd` holds profiles, matchmaking, rewards and missions;
  `room.gd` runs one authoritative match; `net.gd` is the client autoload (WebSocket, or an
  in-app backend when offline).
- `server/`: the dedicated WebSocket server, Docker and Caddy deploy files (see `server/DEPLOY.md`).
- `game3d/`: the 3D board, models, dice and price tags. `ui/`: the UI kit, lobby, popups, HUD,
  and the sound/haptics autoload.
- `tools/`: tests, the balance simulator, Blender build scripts and the store screenshot composer.
- `docs/`: rules (`DESIGN.md`), privacy policy draft, store listing and store art.

## Test
```
godot --headless --path . -s tools/test.gd       # rules engine
godot --headless --path . -s tools/test_net.gd   # service: matchmaking, payouts, rejoin, cheating
godot --headless --path . -s tools/sim.gd -- --games 3000 --tier 1
```

## Play locally against a local server
```
godot --headless --path . res://server/server.tscn
godot --path . -- --server=ws://127.0.0.1:8910 --identity=a
```

## Build
- Debug APK (phone): export preset "Android".
- Emulator APK: preset "Android Emulator" (uses the Compatibility renderer).
- Play Store AAB: preset "Android Release". It's a Gradle build, signed with the upload key kept
  **outside the repo**. Pass the key through environment variables:
  ```
  GODOT_ANDROID_KEYSTORE_RELEASE_PATH=D:/Work/skyloop-release/upload.jks
  GODOT_ANDROID_KEYSTORE_RELEASE_USER=skyloop
  GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=...   # see KEYSTORE-README.txt next to the key
  godot --headless --path . --install-android-build-template --export-release "Android Release" build/skyloop-release.aab
  ```
  Raise `version/code` in `export_presets.cfg` for every upload.
