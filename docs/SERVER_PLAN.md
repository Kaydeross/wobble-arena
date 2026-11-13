# Server plan: self-hosting Wobblers Arena on a NAS

_Runbook for the owner. Nothing here is done for you: you run the NAS, own the domain and hold the tunnel token. The repo only ships the container, the compose file and the client setting._

## 1. What runs

One Node process (`server.js`, image from the repo `Dockerfile`, `node:22-alpine`):

- **Room relay** over WebSocket `/ws` (rooms, host migration, message relay; host-authoritative game, see `docs/PROTOCOL.md`).
- **Account REST API** on the same port (`/api/...`: sign-up, login, cloud save), handled by `accounts.js`.
- **Static web game** from `public/` and **`/health`** for monitoring.
- Bandwidth is small (8 players x 30 Hz JSON per room). A NAS CPU is plenty.

The iOS app reads one address, `wss://<your hostname>/ws`; the REST API is derived from it (`wss` becomes `https`, `/ws` is dropped; `AccountApi.http_base`).

## 2. Environment variables

| Variable | Default | Meaning |
|---|---|---|
| `PORT` | `3000` | Listen port inside the container. |
| `DATA_DIR` | `/data` (compose) | Folder for `db.json` (accounts, cloud saves). Must be a persistent volume. The image default `/tmp/wobble-data` is wiped on redeploy (Render). |
| `REQUIRE_LOGIN` | `1` | Online play needs a signed-in account. `0` lets anyone connect. Keep `1`. |
| `TRUST_PROXY` | off | Where the per-IP limit gets the client address. Unset/`0`: the socket address. `1`: last `x-forwarded-for` entry (one proxy hop you control). `cloudflare`: `cf-connecting-ip`, else the last `x-forwarded-for`. The compose file sets `cloudflare`. Never enable it when the port is reachable without the proxy, or clients can spoof their address. |
| `UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN` | unset | Optional: store accounts in Upstash instead of `db.json`. Both must be set. Only needed if you want the data off the NAS. |
| `CLOUDFLARE_TUNNEL_TOKEN` | none | Compose-only; for the `cloudflared` service. You supply it in `deploy/nas/.env`. |

## 3. Files in this repo

- `deploy/nas/docker-compose.yml`: `wobble` (built from the repo `Dockerfile`, named volume `wobble-data` at `/data`, healthcheck on `/health`, `restart: unless-stopped`) and an optional `cloudflared` service (profile `tunnel`).
- `deploy/nas/.env.example`: placeholders only. Copy to `deploy/nas/.env` (git-ignored).

## 4. Quick start (any Docker host)

1. Copy the repo to the NAS (git clone, or upload; Synology: put it under a shared folder, e.g. `/volume1/docker/wobble-arena`).
2. `cp deploy/nas/.env.example deploy/nas/.env` and fill it in (section 5).
3. From the repo root: `docker compose -f deploy/nas/docker-compose.yml --env-file deploy/nas/.env --profile tunnel up -d --build`
   (omit `--profile tunnel` to test on the LAN first: open `http://<nas-ip>:3000/health`, expect `{"ok":true,...}`).
4. Synology: Container Manager > Project > Create, point at `deploy/nas/docker-compose.yml`. QNAP: Container Station > Applications > Create. TrueNAS SCALE: Apps > Custom App, or run compose from a shell.
5. Update later: `git pull`, then rerun the `up -d --build` command. The volume keeps `db.json`.

## 5. Public access: Cloudflare Tunnel (recommended)

Free, no port forwarding, works behind CGNAT, hides your home IP, gives `wss://` TLS on your own hostname. WebSockets work by default.

What you need to supply: **a domain** (about US$10/yr, on Cloudflare DNS) and **a tunnel token**.

1. Add the domain to Cloudflare (register there, or change your registrar's nameservers to Cloudflare's).
2. Cloudflare dashboard > Zero Trust > Networks > Tunnels > Create a tunnel > Cloudflared. Name it `wobble`.
3. On the install screen choose Docker and copy only the token (the long string after `--token`). Put it in `deploy/nas/.env` as `CLOUDFLARE_TUNNEL_TOKEN`. Treat it like a password; if it leaks, roll it in the dashboard.
4. Public Hostname tab: hostname `play.<your-domain>`, service type **HTTP**, URL **`http://wobble:3000`** (the compose service name; `cloudflared` and `wobble` share the compose network). Cloudflare creates the DNS record.
5. `docker compose ... --profile tunnel up -d`. The tunnel shows Healthy in the dashboard.
6. Check from outside the home network (phone on mobile data): `https://play.<your-domain>/health`.
7. WebSockets: nothing to enable (Cloudflare Network > WebSockets is on by default). Idle connections are fine: the server pings every ~25 s. Cloudflare closes a WebSocket idle for ~100 s without traffic, which the ping prevents.
8. Optional hardening in Cloudflare: WAF rate-limit rule on `/api/login` and `/api/signup`, and "Bot Fight Mode" off for `/ws` if it ever blocks the app (it is not a browser).
9. Remove the host `ports:` mapping from the compose file once the tunnel works, so nothing is exposed on the LAN.

### Alternatives

- **Port forward + DDNS + Let's Encrypt:** forward 443 on the router to a reverse proxy (Caddy or nginx; Synology has a built-in reverse proxy and certificates), keep a DDNS name (Synology DDNS, DuckDNS, or a Cloudflare DNS-only record updated by script), proxy `/ws` with `Upgrade` headers. It exposes your home IP, fails behind CGNAT, and you must set `TRUST_PROXY=1` and make sure only the proxy can reach port 3000.
- **Tailscale Funnel:** `tailscale funnel 3000` gives a public `https://<machine>.<tailnet>.ts.net` with TLS and no domain. Free, but the hostname is not yours, rate limits apply, and it is less suited to a public app. Fine for a friends-only test. Use `TRUST_PROXY=1`.
- **Always-on cloud host (Render paid, Fly.io, a small VPS)** with the same image; set `DATA_DIR` to a persistent disk and `TRUST_PROXY=1`. A good fallback if the NAS is unreliable.

## 6. Pointing the iOS app at it

- Release builds read `godot/data/extra/server.json`: `{"url": "wss://play.<your-domain>/ws"}`. The file ships with an empty `url`; **fill it in before building**. It is public config, not a secret.
- If `url` is empty (or the file is missing/invalid), the app falls back to `ws://127.0.0.1:3000/ws`, which only works in the editor. The editor and tests always use the dev address.
- Players can still change it in Settings > About > "Game server (advanced)". The screen shows `Using: <url> (default|custom)` and a **Reset to default** button. The default is never stored on the device, so a later app update can change it.
- Test before a build: set the Settings field to your `wss://` address in the editor, sign up, create a room, join from a second device.
- **App Review needs the server up and reachable during review** (days). Do not take the NAS down, change the hostname or let the tunnel lapse while a build is in review; create a demo account and give its login in the review notes. Keep the Render/Fly fallback in mind.

## 7. Operations

- **Health check:** `GET /health` returns `{"ok":true,"rooms":N,"players":N,"accounts":"file","saved":false}` (`accounts` is `upstash` when that is used). The compose healthcheck uses it, and `restart: unless-stopped` brings the container back after crashes and reboots.
- **Uptime monitor:** UptimeRobot (free) or Better Stack: HTTPS check on `https://play.<your-domain>/health` every 5 min, alert to email/phone. Add a keyword check for `"ok":true`. Optionally Uptime Kuma on the NAS for LAN-side checks (it cannot see tunnel or ISP outages from inside).
- **Backups of `db.json`:** it holds password hashes and cloud saves. Nightly copy off the volume, e.g. a Synology Task Scheduler / cron job:
  `docker run --rm -v deploy_nas_wobble-data:/data -v /volume1/backups/wobble:/out alpine sh -c 'cp /data/db.json /out/db-$(date +%F).json'` (check the real volume name with `docker volume ls`), keep 14-30 days, and sync the folder to a cloud bucket or a second disk. Test a restore once: stop the container, copy the file back into the volume, start.
- **Logs:** `docker logs -f wobble`. Updates: section 4 step 5.
- **Power/ISP outages:** put the NAS on a UPS; know that a home outage is a game outage (one region, home upload speed).
- **Load test:** before launch, open ~50 WebSocket clients with `tools/wa-client.js` against the public hostname and watch CPU and upload.

## 8. Security notes

- The tunnel token and any Upstash token live only in `deploy/nas/.env` on the NAS. Never commit them or paste them in chat or screenshots. Roll them if exposed.
- Keep `REQUIRE_LOGIN=1`. Put the app behind the tunnel only; remove the LAN port mapping so `wobble` is reachable only through `cloudflared`.
- Set `TRUST_PROXY` only to match your real proxy. With `cloudflare`/`1`, direct access to port 3000 would let a client forge its address and dodge per-IP limits, hence the advice above.
- The server is a relay: the host client is authoritative, so the room server cannot stop cheating (see roadmap B). Do not treat client coin counts as trusted until the server wallet exists.
- Keep the NAS OS, Docker and the `cloudflared` image updated; the image runs as the non-root `node` user.
- Back up `db.json` (section 7); it is the only state.
- Limits in `server.js` (`LIMITS`: rooms, connections, per-IP, rate) already guard abuse; adjust if your NAS is small.

## 9. Roadmap (rough effort)

| Step | What | Effort |
|---|---|---|
| **A. Host it** (this document) | NAS + tunnel, persistent `DATA_DIR`, `wss://` default in the client, `TRUST_PROXY`, health check/uptime alert, nightly backup, load test | 2-4 days (mostly your NAS setup) |
| **B. Trust and resilience** | Guest reconnect / seat hold after a dropped connection; per-weapon damage caps and plausibility checks in `netGuard`; report/block players; server-side wallet replacing client `coins_####` (validated quest/match rewards); shared room registry (Redis) so several instances can run | 2-4 weeks |
| **C. Matchmaking** | Region/ping-aware `quick` play; second region if players are far away | 1-2 weeks, later |
| **D. Dedicated servers** | Headless Godot authoritative servers, only if ranked/competitive play becomes a goal | 2-4 months |

Order: A now, B for App Review and economy safety (guest reconnect, report/block and the wallet matter most), C and D only if the player base needs them.
