#!/usr/bin/env python3
"""Rhythia-reimagined multiplayer relay: room directory + reverse tunnel (docs/RELAY.md).

The host's game keeps one outbound WebSocket open (/v1/host) and gets a room code. Guests open
their own WebSocket (/v1/join) with that code; the relay gives each guest a stream id and forwards
bytes between the guest and the host's tunnel. The game protocol inside (JSON lines, MPProto.gd)
is never read here: the host's game checks every message, the relay only routes, limits and
expires. Python 3.8+ standard library only.
"""
import asyncio
import base64
import hashlib
import json
import os
import secrets
import signal
import ssl
import struct
import sys
import time

PROTO = "rr-relay-1"
CODE_ABC = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # (MPProto.CODE_ABC: no 0 / O / 1 / I)
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def env(name, default, kind=int):
    v = os.environ.get(name)
    if v is None or v == "":
        return default
    return kind(v)


class Cfg:
    def __init__(self):
        self.host = env("RR_RELAY_BIND", "0.0.0.0", str)
        self.port = env("RR_RELAY_PORT", 8080)
        self.public_url = env("RR_RELAY_PUBLIC_URL", "", str).rstrip("/")  # shown in invite pages only
        self.tls_cert = env("RR_TLS_CERT", "", str)
        self.tls_key = env("RR_TLS_KEY", "", str)
        self.trust_proxy = env("RR_TRUST_PROXY", 0) == 1  # take the client address from X-Forwarded-For
        self.max_rooms = env("RR_MAX_ROOMS", 200)
        self.max_rooms_per_ip = env("RR_MAX_ROOMS_PER_IP", 3)
        self.max_guests = env("RR_MAX_GUESTS", 15)  # per room (the game allows 16 players incl. the host)
        self.max_conns = env("RR_MAX_CONNS", 2000)
        self.max_conns_per_ip = env("RR_MAX_CONNS_PER_IP", 24)
        self.host_grace = env("RR_HOST_GRACE", 25)  # s a room waits for its host to reconnect
        self.room_max_age = env("RR_ROOM_MAX_AGE", 12 * 3600)
        self.idle_timeout = env("RR_IDLE_TIMEOUT", 40)  # s without any frame from a connection
        self.join_rate = env("RR_JOIN_RATE", 12)  # join attempts per IP per minute
        self.create_rate = env("RR_CREATE_RATE", 10)  # rooms created per IP per minute
        self.bad_code_limit = env("RR_BAD_CODES", 20)  # unknown codes per IP per 10 minutes
        self.stream_rate = env("RR_STREAM_RATE", 65536)  # guest -> host bytes/s per guest (burst 4x)
        self.host_rate = env("RR_HOST_RATE", 1048576)  # host -> guests bytes/s per room (burst 4x)
        self.max_frame = env("RR_MAX_FRAME", 65536)
        self.max_pending = env("RR_MAX_PENDING", 1048576)  # unsent bytes before a connection is cut
        self.dev_delay_ms = env("RR_DEV_DELAY_MS", 0)  # testing only: extra delay each way
        self.dev_jitter_ms = env("RR_DEV_JITTER_MS", 0)
        self.log_level = env("RR_LOG", "info", str)


CFG = Cfg()
SALT = secrets.token_bytes(16)  # (per run: logs can tell clients apart without holding their address)
STARTED = time.time()
STATS = {"rooms_created": 0, "joins": 0, "joins_refused": 0, "bytes_up": 0, "bytes_down": 0}


def log(level, event, **kw):
    if level == "debug" and CFG.log_level != "debug":
        return
    kw.update(ts=round(time.time(), 3), level=level, event=event)
    sys.stdout.write(json.dumps(kw, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def who(ip):
    return hashlib.sha256(SALT + ip.encode()).hexdigest()[:10]


def now():
    return time.monotonic()


class Bucket:
    def __init__(self, rate, burst):
        self.rate, self.burst, self.level, self.t = float(rate), float(burst), float(burst), now()

    def take(self, n=1.0):
        t = now()
        self.level = min(self.burst, self.level + (t - self.t) * self.rate)
        self.t = t
        if self.level < n:
            return False
        self.level -= n
        return True


# ---------------------------------------------------------------- WebSocket (RFC 6455, server side)
class Closed(Exception):
    pass


class WS:
    def __init__(self, reader, writer, ip):
        self.r, self.w, self.ip = reader, writer, ip
        self.closed = False
        self.last_rx = now()
        self._send_at = 0.0

    async def recv(self):
        """-> (is_text, payload) for the next data message; answers pings, raises Closed."""
        parts, kind = [], None
        while True:
            hdr = await self.r.readexactly(2)
            fin, op, masked, ln = hdr[0] & 0x80, hdr[0] & 0x0F, hdr[1] & 0x80, hdr[1] & 0x7F
            if hdr[0] & 0x70 or not masked:
                await self.close(1002, "protocol error")
                raise Closed("bad frame")
            if ln == 126:
                ln = struct.unpack(">H", await self.r.readexactly(2))[0]
            elif ln == 127:
                ln = struct.unpack(">Q", await self.r.readexactly(8))[0]
            if ln > CFG.max_frame or (op >= 8 and ln > 125):
                await self.close(1009, "frame too large")
                raise Closed("frame too large")
            mask = await self.r.readexactly(4)
            raw = await self.r.readexactly(ln)
            data = (int.from_bytes(raw, "big") ^ int.from_bytes((mask * (ln // 4 + 1))[:ln], "big")).to_bytes(ln, "big") if ln else b""
            self.last_rx = now()
            if op == 8:
                await self.close(1000, "")
                raise Closed("closed by peer")
            if op == 9:
                self._frame(10, data)
                continue
            if op == 10:
                continue
            if op in (1, 2):
                if kind is not None:
                    await self.close(1002, "protocol error")
                    raise Closed("bad fragment")
                kind = op
            elif op != 0 or kind is None:
                await self.close(1002, "protocol error")
                raise Closed("bad opcode")
            parts.append(data)
            if sum(len(p) for p in parts) > CFG.max_frame:
                await self.close(1009, "message too large")
                raise Closed("message too large")
            if fin:
                return kind == 1, b"".join(parts)

    def _frame(self, op, payload):
        if self.closed:
            return
        n = len(payload)
        if n < 126:
            hdr = struct.pack(">BB", 0x80 | op, n)
        elif n < 65536:
            hdr = struct.pack(">BBH", 0x80 | op, 126, n)
        else:
            hdr = struct.pack(">BBQ", 0x80 | op, 127, n)
        if CFG.dev_delay_ms or CFG.dev_jitter_ms:
            d = (CFG.dev_delay_ms + secrets.randbelow(CFG.dev_jitter_ms + 1)) / 1000.0
            t = max(self._send_at, now() + d)  # (order kept: a stream must never be reordered)
            self._send_at = t
            asyncio.get_running_loop().call_later(t - now(), self._write, hdr + payload)
        else:
            self._write(hdr + payload)

    def _write(self, b):
        if self.closed or self.w.is_closing():
            return
        self.w.write(b)
        if self.w.transport.get_write_buffer_size() > CFG.max_pending:
            log("warn", "slow_consumer", who=who(self.ip))
            self.abort()

    def send_text(self, obj):
        self._frame(1, json.dumps(obj, separators=(",", ":")).encode())

    def send_bin(self, b):
        self._frame(2, b)

    async def close(self, code=1000, reason=""):
        if self.closed:
            return
        self._frame(8, struct.pack(">H", code) + reason.encode()[:120])
        if self._send_at > now():  # (test latency: let the delayed frames, this close included, go out first)
            await asyncio.sleep(self._send_at - now() + 0.02)
        self.closed = True
        try:
            await asyncio.wait_for(self.w.drain(), 2)
        except Exception:
            pass
        self.w.close()

    def abort(self):
        self.closed = True
        try:
            self.w.transport.abort()
        except Exception:
            pass


# ---------------------------------------------------------------- rooms
class Room:
    def __init__(self, code, host_ws, hello):
        self.code = code
        self.token = secrets.token_urlsafe(32)  # host credential (resume), never derived from the code
        self.game = str(hello.get("game", ""))[:32]
        self.max_guests = max(1, min(CFG.max_guests, int(hello.get("max", CFG.max_guests))))
        self.host = host_ws
        self.host_ip = host_ws.ip
        self.created = now()
        self.host_lost = 0.0
        self.streams = {}
        self.next_sid = 1
        self.out_bucket = Bucket(CFG.host_rate, CFG.host_rate * 4)


class Relay:
    def __init__(self):
        self.rooms = {}
        self.tombstones = {}  # code -> time it expired (so a late join hears "expired", not "unknown")
        self.conns = 0
        self.conns_ip = {}
        self.join_buckets = {}
        self.create_buckets = {}
        self.bad_codes = {}
        self.all_ws = set()
        self.stopping = False

    # -------- codes
    def new_code(self):
        while True:
            c = "".join(CODE_ABC[secrets.randbelow(32)] for _ in range(8))
            if c not in self.rooms and c not in self.tombstones:
                return c

    @staticmethod
    def norm_code(c):
        c = str(c).upper().replace("-", "").replace(" ", "")
        if len(c) != 8 or any(ch not in CODE_ABC for ch in c):
            return ""
        return c

    @staticmethod
    def show(c):
        return c[:4] + "-" + c[4:]

    def rooms_of(self, ip):
        return sum(1 for r in self.rooms.values() if r.host_ip == ip)

    def end_room(self, room, why):
        if self.rooms.get(room.code) is not room:
            return
        del self.rooms[room.code]
        self.tombstones[room.code] = now()
        if len(self.tombstones) > 50000:  # (bounded: the oldest go first)
            for c in sorted(self.tombstones, key=self.tombstones.get)[:10000]:
                del self.tombstones[c]
        for st in list(room.streams.values()):
            st.send_text({"op": "error", "code": "closed", "msg": why})
            asyncio.ensure_future(st.close(4000, why))
        room.streams.clear()
        log("info", "room_end", room=self.show(room.code), why=why, age=round(now() - room.created))

    async def janitor(self):
        while True:
            await asyncio.sleep(2)
            t = now()
            for room in list(self.rooms.values()):
                if room.host is None and t - room.host_lost > CFG.host_grace:
                    self.end_room(room, "the host didn't come back")
                elif t - room.created > CFG.room_max_age:
                    if room.host:
                        room.host.send_text({"op": "error", "code": "expired", "msg": "the room reached its time limit"})
                        asyncio.ensure_future(room.host.close(4002, "room time limit"))
                    self.end_room(room, "time limit")
            for c, at in list(self.tombstones.items()):
                if t - at > 600:
                    del self.tombstones[c]
            for ws in list(self.all_ws):
                if t - ws.last_rx > CFG.idle_timeout:
                    log("debug", "idle_timeout", who=who(ws.ip))
                    ws.abort()
            for d in (self.join_buckets, self.create_buckets, self.bad_codes):
                for k in [k for k, v in d.items() if t - (v.t if isinstance(v, Bucket) else v[1]) > 900]:
                    del d[k]

    # -------- HTTP / upgrade
    async def handle(self, reader, writer):
        peer = writer.get_extra_info("peername")
        ip = peer[0] if peer else "?"
        try:
            head = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 10)
        except Exception:
            writer.close()
            return
        if len(head) > 8192:
            writer.close()
            return
        lines = head.decode("latin-1").split("\r\n")
        try:
            method, path, _ = lines[0].split(" ", 2)
        except ValueError:
            writer.close()
            return
        hdrs = {}
        for ln in lines[1:]:
            if ":" in ln:
                k, v = ln.split(":", 1)
                hdrs[k.strip().lower()] = v.strip()
        if CFG.trust_proxy and hdrs.get("x-forwarded-for"):
            ip = hdrs["x-forwarded-for"].split(",")[-1].strip()
        path = path.split("?", 1)[0]
        if method != "GET":
            return self.http(writer, 405, {"error": "method"})
        if path == "/health":
            return self.http(writer, 200, self.health())
        if path.startswith("/v1/rooms/"):
            return self.http(writer, 200, self.lookup(ip, path[len("/v1/rooms/"):]))
        if path.startswith("/j/"):
            return self.invite_page(writer, path[3:], hdrs.get("host", ""))
        if path not in ("/v1/host", "/v1/join"):
            return self.http(writer, 404, {"error": "not found"})
        if hdrs.get("upgrade", "").lower() != "websocket" or "sec-websocket-key" not in hdrs:
            return self.http(writer, 426, {"error": "websocket only"})
        if self.stopping:
            return self.http(writer, 503, {"error": "restarting"})
        if self.conns >= CFG.max_conns or self.conns_ip.get(ip, 0) >= CFG.max_conns_per_ip:
            log("warn", "conn_limit", who=who(ip))
            return self.http(writer, 503, {"error": "busy"})
        acc = base64.b64encode(hashlib.sha1((hdrs["sec-websocket-key"] + WS_GUID).encode()).digest()).decode()
        writer.write(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                      "Sec-WebSocket-Accept: %s\r\n\r\n" % acc).encode())
        ws = WS(reader, writer, ip)
        self.conns += 1
        self.conns_ip[ip] = self.conns_ip.get(ip, 0) + 1
        self.all_ws.add(ws)
        try:
            if path == "/v1/host":
                await self.host_session(ws)
            else:
                await self.guest_session(ws)
        except (Closed, asyncio.IncompleteReadError, ConnectionError, asyncio.TimeoutError):
            pass
        except Exception as e:  # (one broken connection must never take the relay down)
            log("error", "session_error", err=repr(e))
        finally:
            self.all_ws.discard(ws)
            self.conns -= 1
            self.conns_ip[ip] -= 1
            if self.conns_ip[ip] <= 0:
                del self.conns_ip[ip]
            if not ws.closed:
                ws.abort()

    def http(self, writer, code, obj):
        body = json.dumps(obj).encode()
        writer.write(("HTTP/1.1 %d X\r\nContent-Type: application/json\r\nContent-Length: %d\r\n"
                      "Cache-Control: no-store\r\nConnection: close\r\n\r\n" % (code, len(body))).encode() + body)
        writer.close()

    def health(self):
        return {"ok": not self.stopping, "proto": PROTO, "rooms": len(self.rooms), "conns": self.conns,
                "streams": sum(len(r.streams) for r in self.rooms.values()), "uptime": round(time.time() - STARTED),
                "stats": STATS}

    def lookup(self, ip, raw):
        if not self.join_bucket(ip).take():
            return {"ok": False, "code": "throttled"}
        c = self.norm_code(raw)
        room = self.rooms.get(c)
        if not room:
            self.note_bad(ip)
            return {"ok": False, "code": "expired" if c in self.tombstones else "not_found"}
        return {"ok": True, "state": "open" if room.host else "host_away", "game": room.game,
                "guests": len(room.streams), "max": room.max_guests}

    def invite_page(self, writer, raw, host_hdr):
        c = self.norm_code(raw)
        code = self.show(c) if c else "?"
        host_hdr = "".join(ch for ch in host_hdr if ch.isalnum() or ch in ".:-[]")[:255]
        base = CFG.public_url or ("https://" + host_hdr if host_hdr else "")
        link = "%s/j/%s" % (base, code)
        body = ("<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width'>"
                "<title>Rhythia-reimagined invite</title><body style='font:16px sans-serif;background:#0b0b0e;"
                "color:#eee;max-width:520px;margin:12vh auto;padding:0 16px'><h2>Rhythia multiplayer invite</h2>"
                "<p>Room code <b style='font-size:1.4em;letter-spacing:2px'>%s</b></p><p>Open Rhythia-reimagined, "
                "go to Multiplayer &gt; Join and paste this link (or the code):</p><p><code>%s</code></p>"
                "</body>" % (code, link.replace("<", "").replace("&", "")))
        b = body.encode()
        writer.write(("HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\n"
                      "Cache-Control: no-store\r\nConnection: close\r\n\r\n" % len(b)).encode() + b)
        writer.close()

    def join_bucket(self, ip):
        b = self.join_buckets.get(ip)
        if b is None:
            b = self.join_buckets[ip] = Bucket(CFG.join_rate / 60.0, CFG.join_rate)
        return b

    def note_bad(self, ip):
        n, t = self.bad_codes.get(ip, (0, now()))
        if now() - t > 600:
            n, t = 0, now()
        self.bad_codes[ip] = (n + 1, t)

    def too_many_bad(self, ip):
        n, t = self.bad_codes.get(ip, (0, now()))
        return now() - t <= 600 and n >= CFG.bad_code_limit

    @staticmethod
    async def first_text(ws):
        is_text, data = await asyncio.wait_for(ws.recv(), 10)
        if not is_text or len(data) > 2048:
            raise ValueError("expected a short JSON hello")
        msg = json.loads(data.decode())
        if not isinstance(msg, dict):
            raise ValueError("expected an object")
        return msg

    # -------- host side
    async def host_session(self, ws):
        try:
            hello = await self.first_text(ws)
        except (ValueError, UnicodeDecodeError):
            ws.send_text({"op": "error", "code": "protocol", "msg": "bad hello"})
            return await ws.close(1008, "bad hello")
        if hello.get("op") != "create" or hello.get("proto") != PROTO:
            ws.send_text({"op": "error", "code": "version", "msg": "relay protocol %s, this relay speaks %s" % (hello.get("proto"), PROTO)})
            return await ws.close(1008, "version")
        room = None
        tok = hello.get("resume")
        if isinstance(tok, str) and tok:
            for r in self.rooms.values():
                if r.host is None and secrets.compare_digest(r.token, tok):
                    room = r
                    break
        if room:
            room.host = ws
            room.host_ip = ws.ip
            log("info", "room_resume", room=self.show(room.code), who=who(ws.ip))
        else:
            cb = self.create_buckets.get(ws.ip)
            if cb is None:
                cb = self.create_buckets[ws.ip] = Bucket(CFG.create_rate / 60.0, CFG.create_rate)
            if not cb.take():
                log("warn", "create_throttled", who=who(ws.ip))
                ws.send_text({"op": "error", "code": "throttled", "msg": "too many rooms created - wait a minute"})
                return await ws.close(4003, "throttled")
            if len(self.rooms) >= CFG.max_rooms or self.rooms_of(ws.ip) >= CFG.max_rooms_per_ip:
                ws.send_text({"op": "error", "code": "busy", "msg": "this relay can't take more rooms right now" if len(self.rooms) >= CFG.max_rooms else "too many rooms from your address"})
                return await ws.close(4003, "busy")
            try:
                room = Room(self.new_code(), ws, hello)
            except (TypeError, ValueError):
                ws.send_text({"op": "error", "code": "protocol", "msg": "bad hello"})
                return await ws.close(1008, "bad hello")
            self.rooms[room.code] = room
            STATS["rooms_created"] += 1
            log("info", "room_create", room=self.show(room.code), who=who(ws.ip), max=room.max_guests)
        ws.send_text({"op": "room", "code": self.show(room.code), "token": room.token, "max": room.max_guests,
                      "grace": CFG.host_grace, "max_frame": CFG.max_frame, "resumed": tok is not None and room.token == tok})
        ended = False
        try:
            while True:
                is_text, data = await ws.recv()
                if is_text:
                    try:
                        m = json.loads(data.decode())
                        op = m.get("op")
                    except Exception:
                        continue  # (a bad control message is ignored, not fatal)
                    if op == "ping":
                        ws.send_text({"op": "pong", "t": m.get("t")})
                    elif op == "close":
                        st = room.streams.pop(m.get("sid"), None)
                        if st:
                            st.send_text({"op": "error", "code": "closed", "msg": "the host closed your connection"})
                            asyncio.ensure_future(st.close(4001, "closed by host"))
                    elif op == "end":
                        ended = True
                        self.end_room(room, "the host closed the room")
                        return await ws.close(1000, "ended")
                    continue
                if len(data) < 4:
                    continue
                sid = struct.unpack(">I", data[:4])[0]
                st = room.streams.get(sid)
                if st is None:
                    continue  # (a guest that just left)
                if not room.out_bucket.take(len(data) - 4):  # (dropping bytes would corrupt the stream: the guest is cut instead)
                    log("warn", "host_rate", room=self.show(room.code), sid=sid)
                    del room.streams[sid]
                    ws.send_text({"op": "close", "sid": sid})
                    st.send_text({"op": "error", "code": "rate", "msg": "the host sent too much data"})
                    asyncio.ensure_future(st.close(4006, "rate"))
                    continue
                STATS["bytes_down"] += len(data) - 4
                st.send_bin(data[4:])
        finally:
            if not ended and self.rooms.get(room.code) is room and room.host is ws:
                room.host = None
                room.host_lost = now()
                for st in list(room.streams.values()):
                    st.send_text({"op": "error", "code": "host_away", "msg": "the host's connection dropped"})
                    asyncio.ensure_future(st.close(4004, "host away"))
                room.streams.clear()
                log("info", "host_lost", room=self.show(room.code))

    # -------- guest side
    async def guest_session(self, ws):
        def refuse(code, msg):
            STATS["joins_refused"] += 1
            ws.send_text({"op": "error", "code": code, "msg": msg})
            return ws.close(4005, code)
        try:
            hello = await self.first_text(ws)
        except (ValueError, UnicodeDecodeError):
            return await refuse("protocol", "bad hello")
        if hello.get("op") != "join":
            return await refuse("protocol", "expected join")
        if hello.get("proto") != PROTO:
            return await refuse("version", "this relay speaks %s" % PROTO)
        if self.too_many_bad(ws.ip) or not self.join_bucket(ws.ip).take():
            log("warn", "join_throttled", who=who(ws.ip))
            return await refuse("throttled", "too many join attempts - wait a minute")
        c = self.norm_code(hello.get("code", ""))
        room = self.rooms.get(c)
        if room is None:
            self.note_bad(ws.ip)
            if c in self.tombstones:
                return await refuse("expired", "that room has closed")
            return await refuse("not_found", "no room with that code")
        if room.host is None:
            return await refuse("host_away", "the host is reconnecting - try again in a few seconds")
        if str(hello.get("game", "")) != room.game:
            return await refuse("game_version", "the host plays %s, you have %s" % (room.game or "?", hello.get("game", "?")))
        if len(room.streams) >= room.max_guests:
            return await refuse("full", "the room is full")
        sid = room.next_sid
        room.next_sid += 1
        room.streams[sid] = ws
        STATS["joins"] += 1
        bucket = Bucket(CFG.stream_rate, CFG.stream_rate * 4)
        host = room.host
        host.send_text({"op": "open", "sid": sid})
        ws.send_text({"op": "joined", "sid": sid, "max_frame": CFG.max_frame})
        log("info", "join", room=self.show(room.code), sid=sid, who=who(ws.ip))
        try:
            while True:
                is_text, data = await ws.recv()
                if is_text:
                    try:
                        m = json.loads(data.decode())
                    except Exception:
                        continue
                    if m.get("op") == "ping":
                        ws.send_text({"op": "pong", "t": m.get("t")})
                    continue
                if room.streams.get(sid) is not ws:
                    return  # (closed by the host / room ended)
                if not bucket.take(len(data)):
                    log("warn", "guest_rate", room=self.show(room.code), sid=sid)
                    ws.send_text({"op": "error", "code": "rate", "msg": "sending too fast"})
                    return await ws.close(4006, "rate")
                STATS["bytes_up"] += len(data)
                room.host.send_bin(struct.pack(">I", sid) + data)
        finally:
            if room.streams.get(sid) is ws:
                del room.streams[sid]
                if room.host:
                    room.host.send_text({"op": "close", "sid": sid})

    async def shutdown(self):
        self.stopping = True
        log("info", "shutdown", rooms=len(self.rooms))
        for room in list(self.rooms.values()):
            if room.host:
                room.host.send_text({"op": "error", "code": "restarting", "msg": "the relay is restarting"})
            self.end_room(room, "relay restarting")
        await asyncio.gather(*[ws.close(1001, "restarting") for ws in list(self.all_ws)], return_exceptions=True)


async def main():
    relay = Relay()
    ctx = None
    if CFG.tls_cert:
        ctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        ctx.load_cert_chain(CFG.tls_cert, CFG.tls_key or None)
    server = await asyncio.start_server(relay.handle, CFG.host, CFG.port, ssl=ctx, limit=CFG.max_frame + 64, backlog=1024)
    log("info", "listening", bind=CFG.host, port=CFG.port, tls=bool(ctx), proto=PROTO)
    jan = asyncio.ensure_future(relay.janitor())
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for s in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(s, stop.set)
        except (NotImplementedError, RuntimeError):  # (Windows: Ctrl+C ends asyncio.run instead)
            pass
    try:
        await stop.wait()
    finally:
        server.close()
        await relay.shutdown()
        jan.cancel()
        log("info", "stopped")


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
