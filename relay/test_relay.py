#!/usr/bin/env python3
"""Relay tests: py -3 relay/test_relay.py   (real sockets on 127.0.0.1; standard library only)"""
import asyncio
import base64
import json
import os
import secrets
import shutil
import ssl
import struct
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rr_relay as R  # noqa: E402


class Client:
    """Minimal WebSocket client (masked frames, like a real one)."""

    @classmethod
    async def open(cls, port, path, tls=None, hello=None):
        c = cls()
        c.r, c.w = await asyncio.open_connection("127.0.0.1", port, ssl=tls, server_hostname="localhost" if tls else None)
        key = base64.b64encode(secrets.token_bytes(16)).decode()
        c.w.write(("GET %s HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                   "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % (path, key)).encode())
        head = await asyncio.wait_for(c.r.readuntil(b"\r\n\r\n"), 5)
        c.status = int(head.split(b" ")[1])
        if hello is not None and c.status == 101:
            c.text(hello)
        return c

    def frame(self, op, payload, mask=True, fin=True):
        n = len(payload)
        b0 = (0x80 if fin else 0) | op
        if n < 126:
            hdr = struct.pack(">BB", b0, (0x80 if mask else 0) | n)
        elif n < 65536:
            hdr = struct.pack(">BBH", b0, (0x80 if mask else 0) | 126, n)
        else:
            hdr = struct.pack(">BBQ", b0, (0x80 if mask else 0) | 127, n)
        if mask:
            m = secrets.token_bytes(4)
            payload = bytes(b ^ m[i & 3] for i, b in enumerate(payload))
            hdr += m
        self.w.write(hdr + payload)

    def text(self, obj):
        self.frame(1, json.dumps(obj).encode())

    def bin(self, b):
        self.frame(2, b)

    async def recv(self, timeout=3.0):
        """-> ("text", obj) | ("bin", bytes) | ("close", code)"""
        async def one():
            h = await self.r.readexactly(2)
            op, ln = h[0] & 15, h[1] & 127
            if ln == 126:
                ln = struct.unpack(">H", await self.r.readexactly(2))[0]
            elif ln == 127:
                ln = struct.unpack(">Q", await self.r.readexactly(8))[0]
            return op, await self.r.readexactly(ln)
        while True:
            try:
                op, data = await asyncio.wait_for(one(), timeout)
            except asyncio.IncompleteReadError:
                return ("close", None)
            if op == 1:
                return ("text", json.loads(data.decode()))
            if op == 2:
                return ("bin", data)
            if op == 8:
                return ("close", struct.unpack(">H", data[:2])[0] if len(data) >= 2 else None)

    async def until(self, pred, timeout=3.0):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            m = await self.recv(end - time.monotonic())
            if pred(m):
                return m
            if m[0] == "close":
                return m
        raise AssertionError("timed out")

    def close(self):
        self.w.close()


def is_op(op):
    return lambda m: m[0] == "text" and m[1].get("op") == op


async def http_get(port, path):
    r, w = await asyncio.open_connection("127.0.0.1", port)
    w.write(("GET %s HTTP/1.1\r\nHost: localhost\r\n\r\n" % path).encode())
    data = await r.read()
    w.close()
    head, body = data.split(b"\r\n\r\n", 1)
    return int(head.split(b" ")[1]), body


HOST_HELLO = {"op": "create", "proto": R.PROTO, "game": "rr-mp-1", "max": 4}


def join_hello(code, game="rr-mp-1", proto=R.PROTO):
    return {"op": "join", "code": code, "proto": proto, "game": game}


class RelayTest(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        asyncio.get_running_loop().set_debug(False)  # (IsolatedAsyncioTestCase turns on debug mode: ~60x slower with 200 sockets)
        self.saved = dict(vars(R.CFG))
        R.CFG.host_grace = 2
        R.CFG.idle_timeout = 40
        R.CFG.join_rate = 600
        R.CFG.create_rate = 6000
        R.CFG.bad_code_limit = 1000
        R.CFG.max_rooms_per_ip = 100
        R.CFG.max_conns_per_ip = 400
        self.relay = R.Relay()
        self.server = await asyncio.start_server(self.relay.handle, "127.0.0.1", 0, limit=R.CFG.max_frame + 64, backlog=1024)
        self.port = self.server.sockets[0].getsockname()[1]
        self.jan = asyncio.ensure_future(self.relay.janitor())

    async def asyncTearDown(self):
        self.server.close()
        await self.relay.shutdown()
        self.jan.cancel()
        vars(R.CFG).update(self.saved)

    async def host(self, **kw):
        h = dict(HOST_HELLO)
        h.update(kw)
        c = await Client.open(self.port, "/v1/host", hello=h)
        m = await c.until(is_op("room"))
        return c, m[1]

    async def guest(self, code, **kw):
        g = await Client.open(self.port, "/v1/join", hello=join_hello(code, **kw))
        m = await g.until(lambda m: m[0] == "text" and m[1].get("op") in ("joined", "error"))
        return g, m[1]

    async def test_health_and_404(self):
        st, body = await http_get(self.port, "/health")
        self.assertEqual(st, 200)
        self.assertEqual(json.loads(body)["rooms"], 0)
        st, _ = await http_get(self.port, "/nope")
        self.assertEqual(st, 404)
        st, _ = await http_get(self.port, "/v1/join")  # (not an upgrade)
        self.assertEqual(st, 426)

    async def test_room_code_and_credentials(self):
        h, room = await self.host()
        self.assertRegex(room["code"], "^[%s]{4}-[%s]{4}$" % (R.CODE_ABC, R.CODE_ABC))
        self.assertGreaterEqual(len(room["token"]), 40)
        self.assertNotIn(room["code"].replace("-", ""), room["token"])
        st, body = await http_get(self.port, "/v1/rooms/" + room["code"].lower())
        self.assertTrue(json.loads(body)["ok"])
        st, body = await http_get(self.port, "/j/" + room["code"])
        self.assertIn(room["code"].encode(), body)
        h.close()

    async def test_forwarding_both_ways_and_isolation(self):
        h, room = await self.host()
        g1, j1 = await self.guest(room["code"])
        g2, j2 = await self.guest(room["code"].replace("-", "").lower())
        self.assertEqual(j1["op"], "joined")
        self.assertEqual(j2["op"], "joined")
        opens = [await h.until(is_op("open")), await h.until(is_op("open"))]
        sids = [m[1]["sid"] for m in opens]
        self.assertEqual(sids, [j1["sid"], j2["sid"]])
        g1.bin(b'{"t":"hello"}\n')
        m = await h.until(lambda m: m[0] == "bin")
        self.assertEqual(struct.unpack(">I", m[1][:4])[0], j1["sid"])
        self.assertEqual(m[1][4:], b'{"t":"hello"}\n')
        h.bin(struct.pack(">I", j2["sid"]) + b"to two\n")
        self.assertEqual(await g2.until(lambda m: m[0] == "bin"), ("bin", b"to two\n"))
        h.bin(struct.pack(">I", j1["sid"]) + b"to one\n")
        self.assertEqual(await g1.until(lambda m: m[0] == "bin"), ("bin", b"to one\n"))
        # a large message split in WebSocket fragments arrives whole and in order
        big = secrets.token_bytes(40000)
        g1.frame(2, big[:20000], fin=False)
        g1.frame(0, big[20000:])
        m = await h.until(lambda m: m[0] == "bin")
        self.assertEqual(m[1][4:], big)
        g1.close()
        m = await h.until(is_op("close"))
        self.assertEqual(m[1]["sid"], j1["sid"])
        for c in (h, g2):
            c.close()

    async def test_refusals(self):
        h, room = await self.host(max=1)
        g, j = await self.guest("ZZZZ-ZZZZ")
        self.assertEqual(j["code"], "not_found")
        g, j = await self.guest("bad")
        self.assertEqual(j["code"], "not_found")
        g, j = await self.guest(room["code"], proto="rr-relay-0")
        self.assertEqual(j["code"], "version")
        g, j = await self.guest(room["code"], game="rr-mp-0")
        self.assertEqual(j["code"], "game_version")
        g1, j = await self.guest(room["code"])
        self.assertEqual(j["op"], "joined")
        g2, j = await self.guest(room["code"])
        self.assertEqual(j["code"], "full")
        h.text({"op": "end"})
        m = await g1.until(is_op("error"))
        self.assertEqual(m[1]["code"], "closed")
        g3, j = await self.guest(room["code"])
        self.assertEqual(j["code"], "expired")

    async def test_kick_closes_only_that_guest(self):
        h, room = await self.host()
        g1, j1 = await self.guest(room["code"])
        g2, j2 = await self.guest(room["code"])
        h.text({"op": "close", "sid": j1["sid"]})
        m = await g1.until(is_op("error"))
        self.assertEqual(m[1]["code"], "closed")
        h.bin(struct.pack(">I", j2["sid"]) + b"still here\n")
        self.assertEqual(await g2.until(lambda m: m[0] == "bin"), ("bin", b"still here\n"))

    async def test_host_drop_resume_and_expiry(self):
        h, room = await self.host()
        g, j = await self.guest(room["code"])
        h.close()
        m = await g.until(is_op("error"))
        self.assertEqual(m[1]["code"], "host_away")
        g2, j = await self.guest(room["code"])
        self.assertEqual(j["code"], "host_away")
        # the host comes back with its credential: same code; the code alone is not enough
        h2, r2 = await self.host(resume=room["token"])
        self.assertEqual(r2["code"], room["code"])
        self.assertTrue(r2["resumed"])
        g3, j = await self.guest(room["code"])
        self.assertEqual(j["op"], "joined")
        h3, r3 = await self.host(resume=room["code"])
        self.assertNotEqual(r3["code"], room["code"])
        # gone for good after the grace time
        h2.close()
        await asyncio.sleep(R.CFG.host_grace + 2.5)
        g4, j = await self.guest(room["code"])
        self.assertEqual(j["code"], "expired")
        h3.close()

    async def test_malformed(self):
        c = await Client.open(self.port, "/v1/join")
        c.frame(1, b"hello", mask=False)  # unmasked client frame
        self.assertEqual((await c.until(lambda m: m[0] == "close"))[1], 1002)
        c = await Client.open(self.port, "/v1/host")
        c.frame(2, b"\x00\x01")  # binary hello
        m = await c.until(is_op("error"))
        self.assertEqual(m[1]["code"], "protocol")
        c = await Client.open(self.port, "/v1/host")
        c.frame(1, b"{not json")
        m = await c.until(is_op("error"))
        self.assertEqual(m[1]["code"], "protocol")
        h, room = await self.host()
        g, j = await self.guest(room["code"])
        g.frame(2, b"x" * (R.CFG.max_frame + 1))
        self.assertEqual((await g.until(lambda m: m[0] == "close"))[1], 1009)
        h.text({"op": "close", "sid": "x"})  # nonsense control: ignored
        h.text({"op": "ping", "t": 5})
        self.assertEqual((await h.until(is_op("pong")))[1]["t"], 5)
        h.bin(b"\x01")  # too short for a stream id: ignored
        h.bin(struct.pack(">I", 999) + b"x")  # unknown stream: ignored
        st, body = await http_get(self.port, "/health")
        self.assertEqual(json.loads(body)["rooms"], 1)

    async def test_throttles_and_limits(self):
        R.CFG.join_rate = 3
        self.relay.join_buckets.clear()
        res = []
        for _ in range(5):
            g, j = await self.guest("ZZZZ-ZZZZ")
            res.append(j["code"])
        self.assertEqual(res.count("throttled"), 2)
        R.CFG.max_rooms_per_ip = 2
        await self.host()
        await self.host()
        c = await Client.open(self.port, "/v1/host", hello=HOST_HELLO)
        m = await c.until(is_op("error"))
        self.assertEqual(m[1]["code"], "busy")
        # creating and ending rooms in a loop is throttled too
        R.CFG.max_rooms_per_ip = 100
        R.CFG.create_rate = 3
        self.relay.create_buckets.clear()
        codes = []
        for _ in range(5):
            c = await Client.open(self.port, "/v1/host", hello=HOST_HELLO)
            m = await c.until(lambda m: m[0] == "text" and m[1].get("op") in ("room", "error"))
            codes.append(m[1].get("code") if m[1]["op"] == "error" else "ok")
            c.text({"op": "end"})
        self.assertEqual(codes.count("throttled"), 2)

    async def test_guest_rate_limit(self):
        R.CFG.stream_rate = 1000
        h, room = await self.host()
        g, j = await self.guest(room["code"])
        for _ in range(10):
            g.bin(b"x" * 1000)
        m = await g.until(is_op("error"))
        self.assertEqual(m[1]["code"], "rate")
        m = await h.until(is_op("close"))
        self.assertEqual(m[1]["sid"], j["sid"])

    async def test_idle_timeout(self):
        R.CFG.idle_timeout = 2
        h, room = await self.host()
        m = await h.until(lambda m: m[0] == "close", timeout=8)
        self.assertEqual(m[0], "close")

    async def test_many_rooms_at_once_then_clean(self):
        async def one(i):
            h, room = await self.host()
            g, j = await self.guest(room["code"])
            g.bin(b"n%d\n" % i)
            m = await h.until(lambda m: m[0] == "bin")
            h.bin(struct.pack(">I", j["sid"]) + m[1][4:])
            echo = await g.until(lambda m: m[0] == "bin")
            h.text({"op": "end"})
            await g.until(lambda m: m[0] == "close")
            h.close()
            return echo[1] == b"n%d\n" % i
        res = await asyncio.gather(*[one(i) for i in range(100)])
        self.assertTrue(all(res))
        await asyncio.sleep(0.5)
        h = self.relay.health()
        self.assertEqual((h["rooms"], h["streams"], h["conns"]), (0, 0, 0))
        self.assertEqual(self.relay.conns_ip, {})

    async def test_dev_latency(self):
        R.CFG.dev_delay_ms = 120
        h, room = await self.host()
        t = time.monotonic()
        h.text({"op": "ping", "t": 1})
        await h.until(is_op("pong"))
        self.assertGreaterEqual(time.monotonic() - t, 0.11)

    async def test_tls(self):
        exe = shutil.which("openssl")
        if not exe:
            self.skipTest("no openssl on PATH")
        d = tempfile.mkdtemp()
        cert, key = os.path.join(d, "c.pem"), os.path.join(d, "k.pem")
        subprocess.run([exe, "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert, "-days", "1",
                        "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost"], check=True, capture_output=True)
        sctx = ssl.create_default_context(ssl.Purpose.CLIENT_AUTH)
        sctx.load_cert_chain(cert, key)
        srv = await asyncio.start_server(self.relay.handle, "127.0.0.1", 0, ssl=sctx)
        port = srv.sockets[0].getsockname()[1]
        cctx = ssl.create_default_context(cafile=cert)
        c = await Client.open(port, "/v1/host", tls=cctx, hello=HOST_HELLO)
        m = await c.until(is_op("room"))
        self.assertIn("code", m[1])
        with self.assertRaises(ssl.SSLError):  # (an untrusted certificate is refused)
            await Client.open(port, "/v1/host", tls=ssl.create_default_context())
        c.close()
        srv.close()
        shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    unittest.main(verbosity=1)
