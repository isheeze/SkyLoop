# Deploying the Skyloop server

One small VPS runs everything for a soft launch: the game server (headless Godot, about 60 MB of RAM
idle) behind Caddy, which gets the HTTPS certificate phones need for `wss://`.

## 1. Rent a VPS
Any provider works. Recommended start: **2 vCPU / 2 GB RAM, Ubuntu 24.04**, in a region near the
players. For a Pakistan launch: Dubai/Bahrain (AWS me-south-1, Azure UAE North), Mumbai or Singapore.
A single box comfortably holds a few hundred concurrent matches; every room is a few kilobytes.

## 2. Point a domain at it
Create an `A` record such as `play.yourdomain.com` that points to the VPS IP address.

## 3. Install Docker and start the server
```bash
curl -fsSL https://get.docker.com | sh
git clone https://github.com/isheeze/SkyLoop.git && cd SkyLoop
SKYLOOP_DOMAIN=play.yourdomain.com docker compose -f server/docker-compose.yml up -d --build
```
Caddy fetches the certificate on first start. Check it with
`docker compose -f server/docker-compose.yml logs -f skyloop`; you should see
`Skyloop server listening on :8910`.

## 4. Point the app at it
In `project.godot`, set:
```
[skyloop]
server_url="wss://play.yourdomain.com"
```
Then rebuild the AAB (see the README). Phones that can't reach the server fall back to offline
play automatically, and their progress carries over (within limits) the first time they connect.

## Operating it
- **Data**: player profiles live in the `skyloop-data` Docker volume (`/data/profiles`). Back it up
  daily, for example `docker run --rm -v skyloop_skyloop-data:/d -v $PWD:/b alpine tar czf /b/profiles-$(date +%F).tgz -C /d .`
- **Updates**: `git pull && docker compose -f server/docker-compose.yml up -d --build`. Matches in
  progress end when the server restarts; deploy during quiet hours.
- **Firewall**: only ports 80 and 443 need to be open. Port 8910 stays internal.
- **Scaling**: profiles are files on one box. Past tens of thousands of daily players, move them to
  a database (Postgres or Redis); `net/backend.gd` `_load`/`_save` are the only places to change.

## Testing locally
```bash
godot --headless --path . res://server/server.tscn
godot --path . -- --server=ws://127.0.0.1:8910 --identity=a
godot --path . -- --server=ws://127.0.0.1:8910 --identity=b
```
From the Android emulator the host machine is `ws://10.0.2.2:8910`.
