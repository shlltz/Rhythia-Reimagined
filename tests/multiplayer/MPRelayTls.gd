extends Node
# The relay over TLS (wss://) inside the real game: relay_e2e.py --tls runs rr_relay.py with a fresh
# self-signed certificate for "localhost". Untrusted certificate = refused; trusted = tunnel + guest
# exchange data both ways. Output @@OUT@@/relay_tls.txt
const OUT = "@@OUT@@/relay_tls.txt"
const CERT = "@@S@@/t/relay_cert.pem"
const RELAY = "wss://localhost:47392"
const Relay = preload("res://mods/replay/MPRelay.gd")
const P = preload("res://mods/replay/MPProto.gd")
var passed = 0
var failed = 0

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	call_deferred("run")

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line("[%7.1f] %s" % [OS.get_ticks_msec() / 1000.0, s]); f.close()

func ok(n, c, d = ""):
	if c: passed += 1
	else: failed += 1
	out(("PASS  " if c else "FAIL  ") + n + ("  " + str(d) if str(d) != "" else ""))

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func run():
	Directory.new().remove(OUT)
	yield(wait(4.0), "completed")
	ok("relay address normalising", Relay.base_url("relay.example.org") == "wss://relay.example.org" and Relay.base_url("https://r.example.org/rr/") == "wss://r.example.org/rr" and Relay.base_url("127.0.0.1:8080") == "ws://127.0.0.1:8080" and Relay.base_url("bad host") == "" and Relay.base_url("<x>") == "")
	var inv = Relay.parse_invite("https://r.example.org/rr/j/abcd-efgh")
	ok("invite parsing", inv.get("base") == "wss://r.example.org/rr" and inv.get("code") == "ABCD-EFGH" and Relay.parse_invite("ABCDEFGH").base == "" and Relay.parse_invite("hello").empty() and Relay.parse_invite("ABCD-EFG0").empty())
	# no trust for the test certificate: refused
	var t0 = Relay.Tunnel.new(RELAY, P.VERSION, 4)
	var t = 0.0
	while t < 12 and t0.state != "reconnecting" and t0.state != "ready":
		t0.poll(OS.get_ticks_msec())
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
	ok("untrusted certificate: refused", t0.state == "reconnecting" and t0.code == "", t0.error_text)
	t0.end()
	t0 = null
	Engine.set_meta("rr_relay_cert", CERT)
	var tu = Relay.Tunnel.new(RELAY, P.VERSION, 4)
	t = 0.0
	while t < 12 and tu.state != "ready":
		tu.poll(OS.get_ticks_msec())
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
	ok("trusted certificate: room over wss", tu.state == "ready" and tu.code != "", tu.code)
	var g = Relay.Guest.new(RELAY, tu.code, P.VERSION)
	t = 0.0
	while t < 12 and g.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		tu.poll(OS.get_ticks_msec())
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
	ok("guest joined over wss", g.get_status() == StreamPeerTCP.STATUS_CONNECTED, g.error_text)
	var s = null
	t = 0.0
	while t < 5 and s == null:
		tu.poll(OS.get_ticks_msec())
		if tu.is_connection_available(): s = tu.take_connection()
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
	var big = PoolByteArray()
	for i in 50000: big.append(i % 251)
	g.put_data(big)
	s.put_data("from host\n".to_utf8())
	tu.flush()
	t = 0.0
	while t < 5 and (s.get_available_bytes() < big.size() or g.get_available_bytes() < 10):
		tu.poll(OS.get_ticks_msec())
		g.get_status()
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
	ok("50 KB guest -> host intact (split in chunks)", s.get_available_bytes() == big.size() and s.get_partial_data(big.size())[1] == big)
	ok("host -> guest", g.get_partial_data(100)[1].get_string_from_utf8() == "from host\n")
	g.disconnect_from_host()
	t = 0.0
	while t < 5 and s.open:
		tu.poll(OS.get_ticks_msec())
		yield(get_tree(), "idle_frame"); t += get_process_delta_time()
	ok("guest leaving closes its stream on the host", !s.open and tu.streams.empty())
	tu.end()
	out("== totals: %d passed, %d failed" % [passed, failed])
	yield(wait(0.5), "completed")
	OS.kill(OS.get_process_id())
