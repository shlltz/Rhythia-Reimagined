# Online lobbies and the relay

Online lobbies let players on different networks play together without port forwarding, a VPN or IP
addresses. The idea comes from e4mc (Minecraft): the host's game keeps one **outbound** connection
to a public relay, and guests reach the host through that relay.

**A relay has to be running somewhere before online lobbies work.** The game has no relay built
in, and this project doesn't run an official one yet. A community can host its own: it's one Python file, or
`docker compose up` (below). Players type the relay's address once; invite links carry it.

## How it fits together

```
 guest game ──wss /v1/join──┐                     ┌── host game: MPHost (lobby rules, MPLobby)
 guest game ──wss /v1/join──┤  relay (rr_relay.py) │      ▲ streams look like TCP connections
                            └──── routes bytes ────┴──wss /v1/host (outbound tunnel, MPRelay.Tunnel)
```

| Part | File | Job |
|---|---|---|
| Game client | `src/replay/MPClient.gd`, `MPMenu.gd` | lobby UI, chat, map pick, match, scores (unchanged), plus online join / host |
| Transport | `src/replay/MPRelay.gd` | `Tunnel` (host's outbound WebSocket, one stream per guest), `Guest` (a guest's WebSocket), both shaped like `StreamPeerTCP` |
| Host authority | `src/replay/MPHost.gd`, `MPLobby.gd` | every guest message is checked here, as on a LAN: names, chat limits, ready / start rules, map identity, score values, kicks |
| Directory + relay | `relay/rr_relay.py` | room codes, host credentials, joins, routing, limits, expiry. It never reads the game's messages |

The game's own protocol doesn't change: one JSON object per line, as on a LAN (`MPProto.gd`). The
relay passes those bytes through untouched. The host's own game still connects to its lobby
directly, and players on the same LAN can still join directly (LAN lobbies list).

**Why WebSocket:** the multiplayer protocol is already a reliable ordered stream (TCP) of small
messages: lobby state, chat, the start time and score updates a few times a second. Notes are
never sent; each game plays the map itself, and the start is synchronised with a clock offset
measured from pings. A WebSocket stream keeps the same guarantees, works over the normal HTTPS port
443 through most firewalls and proxies, and Godot 3 has a TLS WebSocket client built in. No UDP
gameplay channel is needed.

## Player flow

1. Host: **Multiplayer > Create lobby**, type the relay address (saved), **HOST ONLINE**.
2. The lobby shows `ONLINE ROOM ABCD-EFGH` and **COPY INVITE** (`https://relay.example.org/j/ABCD-EFGH`).
   Opened in a browser, that link shows a page with the code and instructions.
3. Friends: **Multiplayer > Join**, paste the invite link (or type the code plus the relay address), **JOIN**.
4. Everything else is the normal lobby: chat, map pick (checked to be the same map), ready, start,
   live scores, results, kick. No Fail is forced in the game's logic for the whole match, and each
   player's own settings come back afterwards.
5. **Leave lobby** on the host ends the room: the relay revokes the code at once.

The top bar shows the connection state: CONNECTING TO THE RELAY, CREATING ROOM, WAITING FOR
PLAYERS / n VIA RELAY, RECONNECTING, RELAY FAILED, plus for guests `RELAYED / PING 114 MS (57 TO
RELAY) / JITTER 3 MS` or `DIRECT / PING ...`. The ping is the real round trip to the host through
the relay, and the second number is the guest's own leg to the relay. Nothing is estimated or faked.

## Relay protocol (`rr-relay-1`)

WebSocket, text messages = JSON control, binary messages = stream data. Limits are env settings (below).

**Host** (`/v1/host`):
- → `{"op":"create","proto":"rr-relay-1","game":"rr-mp-1","max":15,"resume":"<token>"?}`
- ← `{"op":"room","code":"ABCD-EFGH","token":"<43 chars>","grace":25,...}`. The **token** is the host
  credential: random 256 bits, unrelated to the code, never shown, used only to resume after a drop.
- ← `{"op":"open","sid":n}` a guest joined; `{"op":"close","sid":n}` it left.
- ↔ binary `[4-byte stream id][bytes]`.
- → `{"op":"close","sid":n}` cut one guest; `{"op":"end"}` close the room (code revoked).
- ↔ `{"op":"ping","t":..}` / `pong` (relay round trip, keeps the idle timer alive).

**Guest** (`/v1/join`):
- → `{"op":"join","code":"ABCD-EFGH","proto":"rr-relay-1","game":"rr-mp-1"}`
- ← `{"op":"joined","sid":n}` or `{"op":"error","code":...,"msg":...}` then close. Codes: `not_found`,
  `expired`, `full`, `host_away` (try again), `version`, `game_version`, `throttled`, `rate`, `closed`.
- ↔ binary = the raw stream.

**HTTP:** `GET /health` (JSON counts), `GET /v1/rooms/CODE` (exists / full / host away; rate-limited
like joins), `GET /j/CODE` (invite page).

**Room life:** created by a host → open. Host connection drops → `host_away` for `RR_HOST_GRACE`
seconds; guests are disconnected and their games reconnect by themselves, and the host's tunnel reconnects
with its token and **keeps the same code**. Not back in time, `end`, or `RR_ROOM_MAX_AGE` → the code is
dead (joins get `expired` for 10 minutes, then `not_found`). Codes are 8 characters from 32 (40 bits),
made with `secrets`, never reused while a room or its tombstone exists.

## Security and privacy

- **TLS:** the game uses `wss://` for any relay address that isn't `localhost` / `127.x`, and checks the
  certificate against its name (Godot's built-in CA list). An untrusted certificate is refused (tested).
- **A room code is not authority.** It lets a guest *ask* to join. The host's game still decides:
  lobby password, player limit, kicked players can't come back by reconnecting, and every message is
  checked by `MPLobby` (a guest can't act as the host, start matches, or change other players' scores).
  Resuming a room needs the separate host token.
- **Guessing codes:** joins are rate-limited per address (`RR_JOIN_RATE`), and an address that tries
  too many unknown codes (`RR_BAD_CODES` in 10 minutes) is blocked from joining for a while. With 40-bit codes and those limits,
  guessing a live room is impractical.
- **No private data in the lobby:** online lobbies send no LAN addresses to players. Guests never
  learn the host's IP (and the host doesn't see theirs): all traffic goes through the relay.
- **What the relay keeps:** in memory only, while a room lives: code, host token, a counter per
  address for limits. Nothing is written to disk. Logs carry a salted hash of the address (a new
  salt each start), room codes and counts, never message contents.
- **No secrets in the game or the repo:** the relay needs no API key; deployments keep their own
  `.env` (ignored by git).
- **Resource limits:** rooms created per minute, message size, unsent-bytes per connection (slow readers are cut), bytes per
  second per guest and per room, connections per address and in total, rooms per address and in
  total, idle timeout, room lifetime.

## Running a relay

### Local (development / LAN testing)

```bash
py -3 relay/rr_relay.py
```

Listens on `0.0.0.0:8080` without TLS. In the game use `ws://127.0.0.1:8080` (same PC) or
`ws://<this PC's LAN IP>:8080`. Plain `ws://` is for testing only.

### Production (Docker + automatic HTTPS)

Needs: a small Linux server with a public IP (1 vCPU / 512 MB is plenty to start), a domain name
pointing at it (A/AAAA record), ports 80 and 443 open.

```bash
cd relay
cp .env.example .env        # set RELAY_DOMAIN and RR_RELAY_PUBLIC_URL
docker compose up -d --build
curl https://relay.example.org/health
```

Caddy gets and renews the certificate. The relay container runs as a non-root user with a read-only
filesystem, 256 MB memory, 1 CPU and capped processes / open files; logs rotate. Upgrade:
`git pull && docker compose up -d --build`; rooms on the old process end with "the relay is
restarting" and hosts' tunnels reconnect and create new rooms (new codes).

Without Docker: `rr-relay.service` (systemd, same limits) behind Caddy or nginx. nginx needs
`proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade";
proxy_set_header X-Forwarded-For $remote_addr; proxy_read_timeout 120s;`. Set `RR_TRUST_PROXY=1` only
when the relay port is reachable through the proxy alone.

The relay can also serve TLS itself (`RR_TLS_CERT`, `RR_TLS_KEY`), e.g. with a certificate from certbot.

### Settings (environment)

| Variable | Default | Meaning |
|---|---|---|
| `RR_RELAY_BIND` / `RR_RELAY_PORT` | `0.0.0.0` / `8080` | listen address |
| `RR_RELAY_PUBLIC_URL` | (Host header) | base of invite links on the invite page |
| `RR_TLS_CERT` / `RR_TLS_KEY` | none | serve TLS directly |
| `RR_TRUST_PROXY` | `0` | take the client address from `X-Forwarded-For` (behind a proxy) |
| `RR_MAX_ROOMS` / `RR_MAX_ROOMS_PER_IP` | 200 / 3 | rooms in total / per address |
| `RR_MAX_GUESTS` | 15 | guests per room (the lobby's own limit applies too) |
| `RR_MAX_CONNS` / `RR_MAX_CONNS_PER_IP` | 2000 / 24 | open WebSockets |
| `RR_JOIN_RATE` | 12 | join attempts per address per minute |
| `RR_CREATE_RATE` | 10 | rooms created per address per minute |
| `RR_BAD_CODES` | 20 | unknown codes per address per 10 min before joins are refused |
| `RR_STREAM_RATE` / `RR_HOST_RATE` | 64 KB/s / 1 MB/s | guest→host per guest / host→guests per room (bursts 4x) |
| `RR_MAX_FRAME` / `RR_MAX_PENDING` | 64 KB / 1 MB | message size / unsent bytes before a connection is cut |
| `RR_HOST_GRACE` | 25 s | how long a room waits for its host to reconnect |
| `RR_IDLE_TIMEOUT` | 40 s | silence before a connection is dropped (clients ping every 3 s) |
| `RR_ROOM_MAX_AGE` | 12 h | room lifetime |
| `RR_DEV_DELAY_MS` / `RR_DEV_JITTER_MS` | 0 | **testing only**: delay everything the relay sends |
| `RR_LOG` | `info` | `debug` adds idle timeouts |

### Capacity and cost

Measured in the end-to-end test: a 3-player room (host + 2 guests) for ~65 s, including one full
35-second match with live scores, moved **197 KB host→guests and 30 KB guests→host** through the
relay, about 1.5 KB/s down and 0.25 KB/s up per guest.

Load test (this PC, Windows, one Python process holding the relay **and** the test clients): 500 rooms
+ 500 guests = 1,000 relay connections added **139 MB** (an upper bound of ~140 KB per relay
connection, since the test clients are counted too), and the relay forwarded **100,000 small messages in 1.75 s**.

Estimates from those numbers (not measured at scale):
- Live scores send the whole player list to every player, up to 4 times a second (MPLobby), so a room's
  traffic grows with players squared. A 16-player match ≈ 15 guests × 16 entries × ~150 bytes × 4/s ≈
  145 KB/s (~1.2 Mbit/s); a 4-player match ≈ 7 KB/s. Lobby time is much less.
- 100 rooms of 4 players playing at once ≈ 0.7 MB/s (~6 Mbit/s). A small VPS with 1 TB of monthly
  traffic covers ~380 hours of that.
- The 256 MB container limit fits roughly 1,500 connections by the load test above; raise it (and
  `RR_MAX_CONNS`) for more. Past a few thousand players, run more relays on different domains (a room
  lives on one relay).

**Abuse:** only the relay's own limits apply (above). The relay forwards a stream only to a host
that registered a room, and only bytes, never to other addresses, so it can't be used as an open
proxy. A relay that gets abused can lower the limits, or put a firewall / rate limiter in front.

## Tests

- `py -3 relay/test_relay.py`: 13 automated tests on real sockets. Health, code format, credentials,
  forwarding both ways and between rooms, fragmented messages, refusals (unknown, closed, full, versions),
  kick, host drop + resume + expiry, malformed frames, join throttling, room limits, guest rate limit,
  idle timeout, 100 rooms created and torn down at once with nothing left over, test latency, TLS
  (a trusted certificate works, an untrusted one is refused). CI runs it.
- `py -3 tests/multiplayer/relay_e2e.py own|share map.sspm`: a real relay process (40-55 ms added
  latency) and **three real game instances**. Host online, a guest joins by invite link, another by
  bare code, chat, map check, a full match with live scores and results, No Fail forced, a guest's
  connection cut + automatic reconnect as the same player, the host's tunnel cut + resume with the same
  code, wrong-version / unknown-code / closed-room refusals, kick, room end, relay down at startup.
- `py -3 tests/multiplayer/relay_e2e.py own|share map.sspm --tls`: the game against a `wss://` relay with a
  self-signed certificate (refused untrusted, works trusted, 50 KB both ways).

### Testing with two real networks

The tests above all run on one PC. To check a real internet path:

1. Deploy a relay (Docker section) and check `https://<domain>/health`.
2. Host on one network (home Wi-Fi), guest on another (a phone hotspot, or a friend's home).
3. Host: HOST ONLINE with the relay domain, then COPY INVITE and send it. Guest: JOIN, paste.
4. Check the top bar on the guest (RELAYED, ping, relay ping), play a match, then pull the guest's
   network for ~10 s: it should show RECONNECTING and come back as the same player.
5. `docker compose logs relay` shows `room_create`, `join`, `host_lost` / `room_resume`, `room_end`.

## Limits and what isn't done

- **No official relay is running yet.** Online lobbies need someone to deploy one (above).
- **Not yet tested across two real internet connections**: everything above ran on one PC (real
  sockets, real relay process, added latency, TLS). Follow "Testing with two real networks" before relying on it.
- **No packet-loss simulation.** Over TCP/WebSocket, lost packets show up as delay (retransmits), not as
  missing messages. Latency and jitter were simulated; loss would need a network emulator (e.g.
  clumsy on Windows), which isn't set up here.
- **No direct peer-to-peer path** (NAT hole punching). Online traffic always goes through the relay;
  same-LAN players can still join directly from the LAN list. The UI says which one is in use.
- Networks that block outbound WebSockets on 443 (some schools / offices) can't reach the relay; the
  game says it couldn't reach the relay and doesn't pretend otherwise.
- The relay sees the lobby's messages in plain form only inside its own process (TLS protects them
  on the wire); there is no end-to-end encryption between players.
