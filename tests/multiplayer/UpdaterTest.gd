extends Node
# Updates (replay/Updater.gd) against a local web server and a sandbox install folder - never GitHub,
# never the real game folder. A key pair made here signs the test manifests; separately, a manifest
# made by "ssp_mod.py manifest" (signed by openssl with the real private key) must verify against
# the public key built into the game. Checks: a good update is found; a changed manifest, another
# key, a foreign URL and a file that doesn't match its hash are all refused (nothing replaced); an
# install backs up, swaps the pck after the waited-for process ends, confirms on the next "boot";
# rollback puts the old file back; the target refuses an install the game isn't running from.
# Output @@OUT@@/updater.txt
const OUT = "@@OUT@@/updater.txt"
const PORT = 18765
var passed = 0
var failed = 0
var server_pid = 0

func out(s):
	var f = File.new()
	f.open(OUT, File.READ_WRITE if f.file_exists(OUT) else File.WRITE)
	f.seek_end(); f.store_line(s); f.close()

func ok(n, c, d = ""):
	if c: passed += 1
	else: failed += 1
	out(("PASS  " if c else "FAIL  ") + n + ("  " + str(d) if str(d) != "" else ""))

func wait(s):
	yield(get_tree().create_timer(s, true), "timeout")

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	call_deferred("run")

func put(path:String, data:PoolByteArray):
	var f = File.new()
	f.open(path, File.WRITE)
	f.store_buffer(data)
	f.close()

func read(path:String) -> PoolByteArray:
	var f = File.new()
	if f.open(path, File.READ) != OK: return PoolByteArray()
	var b = f.get_buffer(f.get_len())
	f.close()
	return b

func blob(tag:String, n:int) -> PoolByteArray:
	var s = ""
	for i in n: s += tag
	return s.to_utf8()

func sha(b:PoolByteArray) -> String:
	var h = HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(b)
	return h.finish().hex_encode()

# writes srv/update.json + .sig signed with `key`
func publish(srv:String, key:CryptoKey, version:String, url:String, size:int, sum:String, tamper:String = ""):
	var m = to_json({"format": 1, "version": version, "notes": "test", "pck": {"name": "new.pck", "url": url, "size": size, "sha256": sum}}).to_utf8()
	var h = HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(m)
	var sig = Crypto.new().sign(HashingContext.HASH_SHA256, h.finish(), key)
	if tamper != "": m = m.get_string_from_utf8().replace(version, tamper).to_utf8()
	put(srv + "/update.json", m)
	put(srv + "/update.json.sig", sig)

func short_process() -> int: # a process that ends in about 2 s (the helper waits for it)
	return OS.execute("ping", ["-n", "3", "127.0.0.1"], false) if OS.get_name() == "Windows" else OS.execute("sleep", ["2"], false)

func wait_file(p:String, secs:float):
	var t = 0.0
	while t < secs and !File.new().file_exists(p):
		yield(wait(0.25), "completed"); t += 0.25

func run():
	Directory.new().remove(OUT)
	yield(wait(5.0), "completed")
	var root = "@@OUT@@"
	var srv = root + "/srv"
	var box = root + "/sandbox"
	var d = Directory.new()
	for p in [srv, box, srv + "/real"]: d.make_dir_recursive(p)
	for f in ["/SoundSpacePlus.pck", "/_update/applied.txt", "/_update/error.txt"]: d.remove(box + f)
	var old = blob("OLD-PCK!", 4096)
	var new = blob("NEW-PCK?", 5000)
	put(box + "/SoundSpacePlus.pck", old)
	put(srv + "/new.pck", new)
	var bad = new.subarray(0, new.size() - 2)
	put(srv + "/bad.pck", bad)
	# the real manifest (ssp_mod.py manifest, run before this test): only its json + signature are served
	var real_dir = "@@S@@/t/realman"
	var has_real = File.new().file_exists(real_dir + "/update.json")
	if has_real:
		put(srv + "/real/update.json", read(real_dir + "/update.json"))
		put(srv + "/real/update.json.sig", read(real_dir + "/update.json.sig"))
	server_pid = OS.execute("py", ["-3", "-m", "http.server", str(PORT), "--bind", "127.0.0.1", "--directory", ProjectSettings.globalize_path(srv)], false)
	yield(wait(2.0), "completed")
	var base = "http://127.0.0.1:%d" % PORT
	var key = Crypto.new().generate_rsa(2048)
	var pem = key.save_to_string(true)
	var cfg = {"base": base, "pubkey": pem, "dir": ProjectSettings.globalize_path(box), "version": "0.12.2", "channel": "portable", "restart": false}
	Engine.set_meta("rr_update_test", cfg)
	var up = get_tree().root.get_node_or_null("RRUpdater")
	ok("the updater runs in the menu", up != null)
	var U = load("res://mods/replay/Updater.gd")
	ok("version compare", U.newer("0.13.0", "0.12.2") and U.newer("1.0.0", "0.99.99") and !U.newer("0.12.2", "0.12.2") and !U.newer("0.9.9", "0.12.0"))
	# ---- checks
	publish(srv, key, "99.0.0", base + "/new.pck", new.size(), sha(new))
	var r = yield(up.check(), "completed")
	ok("a signed newer release is found", r.state == "available" and r.version == "99.0.0", str(r).left(200))
	publish(srv, key, "99.0.0", base + "/new.pck", new.size(), sha(new), "99.0.1")
	r = yield(up.check(), "completed")
	ok("a manifest changed after signing is refused", r.state == "error" and r.error.find("signature") >= 0, r.get("error", r.state))
	var other = Crypto.new().generate_rsa(2048)
	publish(srv, other, "99.0.0", base + "/new.pck", new.size(), sha(new))
	r = yield(up.check(), "completed")
	ok("a manifest signed by another key is refused", r.state == "error" and r.error.find("signature") >= 0, r.get("error", r.state))
	publish(srv, key, "99.0.0", "https://example.com/new.pck", new.size(), sha(new))
	r = yield(up.check(), "completed")
	ok("a manifest pointing elsewhere is refused", r.state == "error" and r.error.find("points somewhere") >= 0, r.get("error", r.state))
	publish(srv, key, "0.0.1", base + "/new.pck", new.size(), sha(new))
	r = yield(up.check(), "completed")
	ok("an older release: up to date", r.state == "current")
	# ---- a download that doesn't match its hash
	publish(srv, key, "99.0.0", base + "/bad.pck", new.size(), sha(new))
	r = yield(up.check(), "completed")
	var res = yield(up.apply(r.manifest), "completed")
	ok("a file that doesn't match the signed hash is not installed", res.has("error") and res.error.find("doesn't match") >= 0 and read(box + "/SoundSpacePlus.pck") == old and !File.new().file_exists(box + "/_update/SoundSpacePlus.pck.new"), res.get("error", "installed!"))
	# ---- the install
	cfg.wait_pid = short_process()
	Engine.set_meta("rr_update_test", cfg)
	publish(srv, key, "99.0.0", base + "/new.pck", new.size(), sha(new))
	r = yield(up.check(), "completed")
	var t0 = OS.get_ticks_msec()
	res = yield(up.apply(r.manifest), "completed")
	ok("install starts", res.get("ok", false), res.get("error", ""))
	var bak = box + "/_update/backup/SoundSpacePlus-v0.12.2.pck"
	ok("the old pck is backed up first", read(bak) == old)
	ok("a rollback script sits next to it", File.new().file_exists(box + ("/_update/rollback.bat" if OS.get_name() == "Windows" else "/_update/rollback.sh")))
	ok("nothing is swapped while the game (here: the waited-for process) still runs", read(box + "/SoundSpacePlus.pck") == old)
	yield(wait_file(box + "/_update/applied.txt", 20.0), "completed")
	ok("after it ends the helper swaps in the verified file", read(box + "/SoundSpacePlus.pck") == new, "%.1f s%s" % [(OS.get_ticks_msec() - t0) / 1000.0, ("  helper error: " + read(box + "/_update/error.txt").get_string_from_utf8()) if File.new().file_exists(box + "/_update/error.txt") else ""])
	ok("... and removes the staged copy", !File.new().file_exists(box + "/_update/SoundSpacePlus.pck.new"))
	ok("pending update recorded", str(U.state().get("pending", {}).get("to", "")) == "99.0.0")
	cfg.version = "99.0.0" # (the new version starts)
	Engine.set_meta("rr_update_test", cfg)
	up.after_boot()
	var st = U.state()
	ok("the new version confirms the update", !st.has("pending") and str(st.get("last_update", {}).get("to", "")) == "99.0.0")
	# ---- rollback
	d.remove(box + "/_update/applied.txt")
	cfg.wait_pid = short_process()
	Engine.set_meta("rr_update_test", cfg)
	res = up.rollback()
	ok("rollback starts", res.get("ok", false), res.get("error", ""))
	yield(wait_file(box + "/_update/applied.txt", 20.0), "completed")
	ok("rollback puts the old file back", read(box + "/SoundSpacePlus.pck") == old)
	cfg.version = "0.12.2"
	Engine.set_meta("rr_update_test", cfg)
	up.after_boot()
	ok("after the rollback the backup offer is gone", !U.state().has("last_update") and !U.state().has("pending"))
	# ---- where it refuses to install
	var c2 = cfg.duplicate()
	c2.erase("dir")
	Engine.set_meta("rr_update_test", c2)
	ok("test mode without a sandbox folder refuses (never the exe's folder)", U.target().get("why", "").find("sandbox") >= 0, U.target())
	ok("the pck next to the exe isn't the one this test runs (--main-pack): refused", !U.runs_from(OS.get_executable_path().get_base_dir() + "/SoundSpacePlus.pck"))
	ok("the pck this instance really runs is recognised", U.runs_from("@@OUT@@/SoundSpacePlus.pck"))
	c2 = cfg.duplicate()
	c2.channel = "tweaks"
	Engine.set_meta("rr_update_test", c2)
	ok("tweaks builds are pointed to the release page", U.target().get("why", "").find("portable") >= 0)
	# ---- the real key: openssl's signature verifies against the key built into the game
	if has_real:
		var c3 = cfg.duplicate()
		c3.erase("pubkey")
		c3.base = base + "/real"
		Engine.set_meta("rr_update_test", c3)
		r = yield(up.check(), "completed")
		ok("a manifest from ssp_mod.py manifest verifies with the built-in key", r.state in ["current", "available"], str(r).left(200))
	else:
		ok("real manifest present (run ssp_mod.py manifest --out tests/multiplayer/t/realman first)", false)
	# ---- the Updates section as a public (portable) build shows it, with an update found
	Engine.set_meta("rr_update_test", cfg)
	publish(srv, key, "99.0.0", base + "/new.pck", new.size(), sha(new))
	yield(up.check(), "completed")
	var menu = get_tree().root.get_node_or_null("Menu")
	if menu:
		menu.open_customize()
		yield(wait(0.6), "completed")
		var cp = menu.get_node("ReimaginedPanel")
		cp.show_tab("storage", false)
		yield(wait(0.4), "completed")
		ok("Storage tab: INSTALL offered for the found version", cp.upd_w.has("_upd_install") and !cp.upd_w._upd_install.disabled and cp.upd_w._upd_install.text == "INSTALL 99.0.0", cp.upd_w.get("status").text if cp.upd_w.has("status") else "")
		if !OS.window_minimized:
			yield(VisualServer, "frame_post_draw")
			var img = get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("@@OUT@@/up_storage.png")
	Engine.remove_meta("rr_update_test")
	OS.kill(server_pid)
	out("== totals: %d passed, %d failed" % [passed, failed])
	OS.kill(OS.get_process_id())
