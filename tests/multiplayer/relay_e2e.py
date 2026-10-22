#!/usr/bin/env python3
"""End-to-end online lobby test: a real relay process + three real game instances.

py -3 relay_e2e.py own|share path/to/map.sspm [delay_ms]
py -3 relay_e2e.py own|share path/to/map.sspm --tls      (wss:// with a fresh self-signed certificate, MPRelayTls.gd)

Starts relay/rr_relay.py on 127.0.0.1:47390 (RR_DEV_DELAY_MS adds latency to everything the relay sends,
default 40 ms + up to 15 ms jitter), runs MPRelayA/B/C.gd through mpbench.py, stops the relay, and
prints the per-instance totals plus the relay's own log counts. The relay's JSON log goes to t/relay.log.
"""
import json
import shutil
import os
import subprocess
import sys
import time
import urllib.request

S = os.path.dirname(os.path.abspath(__file__))
kind, mp = sys.argv[1], sys.argv[2]
tls = "--tls" in sys.argv
delay = sys.argv[3] if len(sys.argv) > 3 and not tls else "40"
port = "47392" if tls else "47390"
env = dict(os.environ, RR_RELAY_BIND="127.0.0.1", RR_RELAY_PORT=port, RR_DEV_DELAY_MS="0" if tls else delay,
           RR_DEV_JITTER_MS="0" if tls else "15", RR_HOST_GRACE="25")
os.makedirs(os.path.join(S, "t"), exist_ok=True)
if tls:
    cert, key = os.path.join(S, "t", "relay_cert.pem"), os.path.join(S, "t", "relay_key.pem")
    subprocess.run([shutil.which("openssl"), "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
                    "-days", "1", "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost"], check=True, capture_output=True)
    env.update(RR_TLS_CERT=cert, RR_TLS_KEY=key)
for f in ("relay_room.txt", "relay_b_ok.txt"):
    try:
        os.remove(os.path.join(S, "t", f))
    except OSError:
        pass
log = open(os.path.join(S, "t", "relay.log"), "w")
relay = subprocess.Popen([sys.executable, os.path.join(S, "..", "..", "relay", "rr_relay.py")], env=env, stdout=log, stderr=subprocess.STDOUT)
try:
    for _ in range(50):
        try:
            h = json.load(urllib.request.urlopen(("https" if tls else "http") + "://localhost:%s/health" % port, timeout=1,
                                                 context=__import__("ssl").create_default_context(cafile=cert) if tls else None))
            break
        except Exception:
            time.sleep(0.1)
    else:
        sys.exit("relay didn't start")
    print("relay up:", h)
    if tls:
        subprocess.run([sys.executable, os.path.join(S, "mpbench.py"), kind, "T=MPRelayTls.gd", "90", "T=" + mp], cwd=S)
    else:
        subprocess.run([sys.executable, os.path.join(S, "mpbench.py"), kind, "A=MPRelayA.gd,B=MPRelayB.gd,C=MPRelayC.gd", "300",
                        "A=%s;B=%s;C=%s" % (mp, mp, mp)], cwd=S)
        print("relay after:", json.load(urllib.request.urlopen("http://127.0.0.1:47390/health", timeout=2)))
finally:
    relay.terminate()
    relay.wait(10)
    log.close()
for inst, fn in ((("T", "relay_tls.txt"),) if tls else (("A", "relay_a.txt"), ("B", "relay_b.txt"), ("C", "relay_c.txt"))):
    p = os.path.join(S, "t", inst, fn)
    lines = open(p, encoding="utf-8").read().splitlines() if os.path.exists(p) else []
    print(inst, [l for l in lines if "FAIL" in l or "== totals" in l] or "no output")
events = {}
for line in open(os.path.join(S, "t", "relay.log"), encoding="utf-8"):
    try:
        e = json.loads(line)["event"]
        events[e] = events.get(e, 0) + 1
    except Exception:
        pass
print("relay events:", events)
