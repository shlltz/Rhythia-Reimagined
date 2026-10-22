extends Node
# Rhythia-reimagined updates (Customize > Storage > Updates; a check at start when switched on, at
# most once a day). A release carries update.json + update.json.sig + the game's pck as assets
# (ssp_mod.py manifest). Nothing downloaded is used before it is verified:
#   1. update.json's RSA / SHA-256 signature against the public key built into the game,
#   2. then the pck's size + SHA-256 against the signed manifest.
# Only portable builds replace their own pck: the current one is copied to _update/backup first, then
# a helper this script writes itself (never downloaded; it only copies the verified file) waits for
# the game to close, swaps the pck and starts the game again. The new version confirms it booted; a
# rollback (here, or rollback.bat / rollback.sh next to the backup if it doesn't start) puts the
# backup back. Tweaks / Android builds are told about a new version and get the release page. A
# personal build ("own") never updates itself. Never runs when the game was started on another pck
# (--main-pack: the test harness), so it can't touch an install it isn't running from.

signal checked(result)
signal progress(text)

const CHANNEL = "@@CHANNEL@@"
const VERSION = "@@VERSION@@"
const BUILD = "@@BUILD_ID@@"     # (new for every build: see runs_from)
const REPO = "shlltz/Rhythia-Reimagined"
const API = "https://api.github.com/repos/shlltz/Rhythia-Reimagined/releases/latest"
const PAGE = "https://github.com/shlltz/Rhythia-Reimagined/releases/latest"
const ASSET_BASE = "https://github.com/shlltz/Rhythia-Reimagined/releases/download/"
const STATE = "user://rr_update.json"
const DAY = 86400

var busy:bool = false
var last:Dictionary = {}         # last check result
var _http:HTTPRequest

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.timeout = 30
	add_child(_http)
	call_deferred("_boot")

func _boot():
	after_boot()
	if auto_on() and can_check() and OS.get_unix_time() - int(state().get("last_check", 0)) > DAY:
		var r = yield(check(), "completed")
		if r.state == "available":
			Globals.notify(Globals.NOTIFY_INFO, "Rhythia-reimagined %s is out: Customize > Storage > Updates" % r.version, "Updates")

# ------------------------------------------------------------------ settings / state
static func test() -> Dictionary: # (test harness only: honoured in personal builds, never in public ones)
	return Engine.get_meta("rr_update_test") if CHANNEL == "own" and Engine.has_meta("rr_update_test") else {}

static func channel() -> String:
	return str(test().get("channel", CHANNEL))

static func current() -> String:
	return str(test().get("version", VERSION))

static func auto_on() -> bool:
	return bool(load("res://mods/replay/Reimagined.gd").val("update_check")) and channel() != "own"

static func can_check() -> bool:
	return channel() != "own" or test().size() > 0

static func state() -> Dictionary:
	var f = File.new()
	if f.open(STATE, File.READ) != OK: return {}
	var r = JSON.parse(f.get_as_text())
	f.close()
	return r.result if r.error == OK and r.result is Dictionary else {}

static func save_state(d:Dictionary):
	var f = File.new()
	if f.open(STATE, File.WRITE) == OK:
		f.store_string(to_json(d))
		f.close()

static func newer(a:String, b:String) -> bool: # a > b ("0.13.0" > "0.12.2")
	var x = a.split(".")
	var y = b.split(".")
	for i in 3:
		var p = int(x[i]) if i < x.size() else 0
		var q = int(y[i]) if i < y.size() else 0
		if p != q: return p > q
	return false

static func valid_version(v:String) -> bool:
	var re = RegEx.new()
	re.compile("^\\d+\\.\\d+\\.\\d+$")
	return re.search(v) != null

# ------------------------------------------------------------------ check
# -> {state: available | current | error, version, notes, manifest, error}
func check():
	if busy:
		yield(get_tree(), "idle_frame")
		return {"state": "error", "error": "already busy"}
	busy = true
	var t = test()
	var murl = ""
	var surl = ""
	if t.has("base"):
		murl = t.base + "/update.json"
		surl = t.base + "/update.json.sig"
	else:
		var rel = yield(_fetch(API), "completed")
		if rel.error != "":
			return _checked({"state": "error", "error": "can't reach GitHub (%s)" % rel.error})
		var j = JSON.parse(rel.body.get_string_from_utf8())
		if j.error != OK or !(j.result is Dictionary):
			return _checked({"state": "error", "error": "unexpected answer from GitHub"})
		for a in j.result.get("assets", []):
			if a.get("name") == "update.json": murl = str(a.get("browser_download_url", ""))
			if a.get("name") == "update.json.sig": surl = str(a.get("browser_download_url", ""))
		if murl == "" or surl == "":
			return _checked({"state": "current", "version": current(), "note": "the latest release has no update manifest"})
	var m = yield(_fetch(murl), "completed")
	if m.error != "": return _checked({"state": "error", "error": "manifest: " + m.error})
	var s = yield(_fetch(surl), "completed")
	if s.error != "": return _checked({"state": "error", "error": "signature: " + s.error})
	var r = verify_manifest(m.body, s.body)
	if r.has("error"): return _checked({"state": "error", "error": r.error})
	var man = r.manifest
	var st = state()
	st.last_check = OS.get_unix_time()
	save_state(st)
	if !newer(man.version, current()):
		return _checked({"state": "current", "version": current()})
	return _checked({"state": "available", "version": man.version, "notes": str(man.get("notes", "")), "manifest": man})

func _checked(r:Dictionary) -> Dictionary:
	busy = false
	last = r
	emit_signal("checked", r)
	return r

# the signature first, then the manifest's own fields; -> {manifest} or {error}
static func verify_manifest(body:PoolByteArray, sig:PoolByteArray) -> Dictionary:
	var pem = str(test().get("pubkey", ""))
	if pem == "":
		var f = File.new()
		if f.open("res://mods/replay/update_key.pub", File.READ) != OK: return {"error": "no update key in this build"}
		pem = f.get_as_text()
		f.close()
	var key = CryptoKey.new()
	if key.load_from_string(pem, true) != OK: return {"error": "bad update key"}
	if sig.size() == 0 or !Crypto.new().verify(HashingContext.HASH_SHA256, _sha256(body), sig, key):
		return {"error": "the update's signature doesn't match: not installed"}
	var j = JSON.parse(body.get_string_from_utf8())
	if j.error != OK or !(j.result is Dictionary): return {"error": "unreadable manifest"}
	var m = j.result
	var p = m.get("pck", {})
	if int(m.get("format", 0)) != 1 or !valid_version(str(m.get("version", ""))) or !(p is Dictionary):
		return {"error": "manifest in an unknown format"}
	var base = str(test().get("base", ""))
	var url = str(p.get("url", ""))
	if !(url.begins_with(ASSET_BASE) or (base != "" and url.begins_with(base + "/"))):
		return {"error": "the update points somewhere other than this project's releases"}
	if int(p.get("size", 0)) <= 0 or str(p.get("sha256", "")).length() != 64:
		return {"error": "manifest without a file size / hash"}
	return {"manifest": m}

static func _sha256(b:PoolByteArray) -> PoolByteArray:
	var h = HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(b)
	return h.finish()

static func file_sha256(path:String) -> String:
	var f = File.new()
	if f.open(path, File.READ) != OK: return ""
	var h = HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	while f.get_position() < f.get_len():
		h.update(f.get_buffer(1 << 20))
	f.close()
	return h.finish().hex_encode()

# GET -> {error, code, body}
func _fetch(url:String, to_file:String = ""):
	_http.download_file = to_file
	var err = _http.request(url, ["User-Agent: Rhythia-reimagined-updater", "Accept: */*"])
	if err != OK:
		yield(get_tree(), "idle_frame")
		return {"error": "request failed (%d)" % err, "code": 0, "body": PoolByteArray()}
	var r = yield(_http, "request_completed")
	if r[0] != HTTPRequest.RESULT_SUCCESS: return {"error": "network error %d" % r[0], "code": r[1], "body": PoolByteArray()}
	if r[1] != 200: return {"error": "HTTP %d" % r[1], "code": r[1], "body": PoolByteArray()}
	return {"error": "", "code": r[1], "body": r[3]}

# ------------------------------------------------------------------ install (portable builds)
# where this build's pck is, or {why} when it can't replace itself. Changes nothing on disk.
static func target() -> Dictionary:
	var t = test()
	if channel() != "portable": return {"why": "only the portable builds update themselves: get the new version from the release page"}
	if t.size() > 0 and !t.has("dir"): return {"why": "test run without a sandbox folder: nothing is replaced"}
	var dir = str(t.get("dir", OS.get_executable_path().get_base_dir()))
	var pck = dir + "/SoundSpacePlus.pck"
	if !File.new().file_exists(pck): return {"why": "no SoundSpacePlus.pck next to the game"}
	if !t.has("dir") and !runs_from(pck): return {"why": "the game wasn't started from the SoundSpacePlus.pck next to it: nothing is replaced"}
	return {"dir": dir, "pck": pck, "exe": OS.get_executable_path()}

# is `pck` (a file on disk) the pck this game runs from? Its index points to its Updater.gd; that
# text carries a build id made for each build, so the same text = the same build. (Engine options
# such as --main-pack never show in OS.get_cmdline_args, so they can't be checked directly.)
static func runs_from(pck:String) -> bool:
	var mine = File.new()
	if mine.open("res://mods/replay/Updater.gd", File.READ) != OK: return false
	var want = mine.get_buffer(mine.get_len())
	mine.close()
	var f = File.new()
	if f.open(pck, File.READ) != OK: return false
	var ok = false
	var name = "res://mods/replay/Updater.gd"
	if f.get_len() > 92 and f.get_buffer(4).get_string_from_ascii() == "GDPC":
		f.seek(84)
		var n = f.get_32()
		for _i in min(n, 200000):
			var l = f.get_32()
			if l <= 0 or l > 4096: break
			var p = f.get_buffer(l)
			var off = f.get_64()
			var size = f.get_64()
			f.get_buffer(16)
			if l >= name.length() and p.subarray(0, name.length() - 1).get_string_from_ascii() == name and (l == name.length() or p[name.length()] == 0):
				if size == want.size():
					f.seek(off)
					ok = f.get_buffer(size) == want
				break
	f.close()
	return ok

func apply(man:Dictionary):
	if busy:
		yield(get_tree(), "idle_frame")
		return {"error": "already busy"}
	var tg = target()
	if tg.has("why"):
		yield(get_tree(), "idle_frame")
		return {"error": tg.why}
	if Directory.new().make_dir_recursive(tg.dir + "/_update/backup") != OK:
		yield(get_tree(), "idle_frame")
		return {"error": "the game folder isn't writable: move it to a folder you can write to, or update by hand"}
	busy = true
	var stage = tg.dir + "/_update/SoundSpacePlus.pck.new"
	Directory.new().remove(stage)
	emit_signal("progress", "Downloading %s (%.1f MB)..." % [man.version, man.pck["size"] / 1048576.0])
	var r = yield(_fetch(str(man.pck.url), stage), "completed")
	if r.error != "":
		busy = false
		Directory.new().remove(stage)
		return {"error": "download: " + r.error}
	emit_signal("progress", "Checking the download...")
	var f = File.new()
	var size = f.get_len() if f.open(stage, File.READ) == OK else -1
	f.close()
	var sum = file_sha256(stage)
	if size != int(man.pck["size"]) or sum != str(man.pck.sha256).to_lower():
		busy = false
		Directory.new().remove(stage)
		return {"error": "the downloaded file doesn't match the signed manifest (size %d, hash %s...): not installed" % [size, sum.left(12)]}
	# back up the current pck (and keep a way back that works without the game)
	var bak = "%s/_update/backup/SoundSpacePlus-v%s.pck" % [tg.dir, current()]
	if Directory.new().copy(tg.pck, bak) != OK or file_sha256(bak) != file_sha256(tg.pck):
		busy = false
		return {"error": "couldn't back up the current game file: not installed"}
	_write_rollback_script(tg, bak)
	var st = state()
	st.pending = {"from": current(), "to": man.version, "backup": bak, "pck": tg.pck, "at": OS.get_unix_time()}
	save_state(st)
	emit_signal("progress", "Installing: the game closes and starts again...")
	var ok = _run_helper(tg, stage, true)
	busy = false
	if !ok: return {"error": "couldn't start the installer helper"}
	return {"ok": true}

# rollback to the backup of the last update
func rollback():
	var st = state()
	var lu = st.get("last_update", {})
	var tg = target()
	if tg.has("why"): return {"error": tg.why}
	if !(lu is Dictionary) or !File.new().file_exists(str(lu.get("backup", ""))): return {"error": "no backup of an earlier version"}
	st.pending = {"from": current(), "to": str(lu.get("from", "")), "backup": "", "pck": tg.pck, "at": OS.get_unix_time(), "rollback": true}
	save_state(st)
	if !_run_helper(tg, str(lu.backup), false): return {"error": "couldn't start the helper"}
	return {"ok": true}

# a small script written here (not downloaded): wait for the game to close, copy the verified file
# over the pck, start the game again
func _run_helper(tg:Dictionary, src:String, move:bool) -> bool:
	var t = test()
	var pid = int(t.get("wait_pid", OS.get_process_id()))
	var restart = bool(t.get("restart", true))
	var dir = tg.dir + "/_update"
	var gsrc = ProjectSettings.globalize_path(src)
	var gpck = ProjectSettings.globalize_path(tg.pck)
	var gdone = ProjectSettings.globalize_path(dir + "/applied.txt")
	Directory.new().remove(dir + "/applied.txt")
	Directory.new().remove(dir + "/error.txt")
	var f = File.new()
	if OS.get_name() == "Windows":
		var ps = dir + "/apply.ps1"
		if f.open(ps, File.WRITE) != OK: return false
		f.store_string("$ErrorActionPreference = 'Stop'\r\ntry {\r\n")
		f.store_string("for ($i = 0; $i -lt 600; $i++) { if (-not (Get-Process -Id %d -ErrorAction SilentlyContinue)) { break }; Start-Sleep -Milliseconds 200 }\r\n" % pid)
		f.store_string("Copy-Item -LiteralPath %s -Destination %s -Force\r\n" % [_ps(gsrc), _ps(gpck)])
		if move: f.store_string("Remove-Item -LiteralPath %s -Force\r\n" % _ps(gsrc))
		f.store_string("Set-Content -LiteralPath %s -Value 'ok'\r\n" % _ps(gdone))
		if restart: f.store_string("Start-Process -FilePath %s -WorkingDirectory %s\r\n" % [_ps(ProjectSettings.globalize_path(tg.exe)), _ps(ProjectSettings.globalize_path(tg.dir))])
		f.store_string("} catch { Set-Content -LiteralPath %s -Value $_.ToString() }\r\n" % _ps(ProjectSettings.globalize_path(dir + "/error.txt")))
		f.close()
		var gps = ProjectSettings.globalize_path(ps)
		return OS.execute("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", gps], false) > 0 # (Godot 3.6 quotes each argument itself)
	var sh = dir + "/apply.sh"
	if f.open(sh, File.WRITE) != OK: return false
	f.store_string("#!/bin/sh\ni=0\nwhile kill -0 %d 2>/dev/null && [ $i -lt 600 ]; do sleep 0.2; i=$((i+1)); done\n" % pid)
	f.store_string("cp -f %s %s || exit 1\n" % [_sh(gsrc), _sh(gpck)])
	if move: f.store_string("rm -f %s\n" % _sh(gsrc))
	f.store_string("echo ok > %s\n" % _sh(gdone))
	if restart: f.store_string("cd %s && nohup %s >/dev/null 2>&1 &\n" % [_sh(ProjectSettings.globalize_path(tg.dir)), _sh(ProjectSettings.globalize_path(tg.exe))])
	f.close()
	return OS.execute("/bin/sh", [ProjectSettings.globalize_path(sh)], false) > 0

func _write_rollback_script(tg:Dictionary, bak:String):
	var f = File.new()
	var gb = ProjectSettings.globalize_path(bak)
	var gp = ProjectSettings.globalize_path(tg.pck)
	if OS.get_name() == "Windows":
		if f.open(tg.dir + "/_update/rollback.bat", File.WRITE) == OK:
			f.store_string("@echo off\r\nrem Puts back the game file from before the last update (close the game first).\r\ncopy /Y \"%s\" \"%s\"\r\npause\r\n" % [gb.replace("/", "\\"), gp.replace("/", "\\")])
			f.close()
	elif f.open(tg.dir + "/_update/rollback.sh", File.WRITE) == OK:
		f.store_string("#!/bin/sh\n# Puts back the game file from before the last update (close the game first).\ncp -f %s %s\n" % [_sh(gb), _sh(gp)])
		f.close()

static func _ps(s:String) -> String: # PowerShell single-quoted literal
	return "'" + s.replace("'", "''") + "'"

static func _sh(s:String) -> String: # sh single-quoted literal
	return "'" + s.replace("'", "'\\''") + "'"

# the first start after an update / rollback: did it take?
func after_boot():
	var st = state()
	var p = st.get("pending")
	if !(p is Dictionary): return
	var to = str(p.get("to", ""))
	if current() == to:
		if !p.get("rollback", false):
			st.last_update = {"from": str(p.get("from", "")), "to": to, "backup": str(p.get("backup", "")), "at": int(p.get("at", 0))}
			Globals.notify(Globals.NOTIFY_SUCCEED, "Updated to %s (the old version is kept: Customize > Storage > Updates can roll back)" % to, "Updates")
		else:
			st.erase("last_update")
			Globals.notify(Globals.NOTIFY_SUCCEED, "Rolled back to %s" % to, "Updates")
	else:
		var ef = str(p.get("pck", "")).get_base_dir() + "/_update/error.txt"
		var why = ""
		var f = File.new()
		if f.open(ef, File.READ) == OK:
			why = " (" + f.get_as_text().strip_edges().left(160) + ")"
			f.close()
		Globals.notify(Globals.NOTIFY_WARN, "The update to %s didn't install; still on %s%s" % [to, current(), why], "Updates")
	st.erase("pending")
	save_state(st)
