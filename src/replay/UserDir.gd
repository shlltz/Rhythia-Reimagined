extends Reference
# Move the game's user folder (%APPDATA%\SoundSpacePlus: maps, replays, scores, settings) to another
# drive. Windows only. The game can't move a folder it has open, so it writes a PowerShell script to
# %TEMP%, starts it in a console window and quits. The script waits for the game to close, copies
# everything (robocopy), checks the copy (file count + bytes), puts a directory junction at the old
# path pointing to the new folder and only then deletes the old copy, and starts the game again.
# Everything that reads user:// keeps working through the junction. "Move back" does the reverse.
# If anything fails before the switch, nothing is deleted.

const MARKER = "user://.rr_location.txt" # written by the script: where the folder really is

static func supported() -> bool:
	return OS.get_name() == "Windows"

static func default_path() -> String:
	return OS.get_user_data_dir().replace("/", "\\")

# the real folder (the junction target after a move)
static func location() -> String:
	var f = File.new()
	if f.open(MARKER, File.READ) == OK:
		var t = f.get_as_text().strip_edges()
		f.close()
		if t != "" and Directory.new().dir_exists(t): return t
	return default_path()

static func moved() -> bool:
	return location() != default_path()

static func target_for(picked:String) -> String:
	var p = picked.replace("/", "\\").rstrip("\\")
	if p.get_file().to_lower() != "soundspaceplus": p += "\\SoundSpacePlus"
	return p

# "" = fine, else why not
static func check(dest:String) -> String:
	if dest == "": return "No folder picked."
	if dest.length() < 4 or dest.substr(1, 2) != ":\\": return "Pick a folder on a drive (like D:\\Games)."
	var cur = location().to_lower() + "\\"
	var d = dest.to_lower() + "\\"
	if d.begins_with(cur) or cur.begins_with(d): return "The new folder can't be inside the current user folder (or the other way round)."
	if d.begins_with(default_path().to_lower() + "\\"): return "Pick a folder outside the current user folder."
	var dir = Directory.new()
	if dir.dir_exists(dest) and dir.open(dest) == OK:
		dir.list_dir_begin(true, false)
		var n = dir.get_next()
		dir.list_dir_end()
		if n != "": return "\"%s\" already has files in it - pick an empty folder." % dest
	return ""

# dest "" = move back to the default place. Quits the game on success.
static func start(tree:SceneTree, dest:String) -> String:
	var tmp = OS.get_environment("TEMP")
	if tmp == "": return "No TEMP folder."
	var script = tmp.replace("\\", "/") + "/rr_move_userdir.ps1"
	var f = File.new()
	if f.open(script, File.WRITE) != OK: return "Couldn't write the helper script."
	f.store_string(PS)
	f.close()
	var args = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script.replace("/", "\\"),
		"-Link", default_path(), "-Exe", OS.get_executable_path().replace("/", "\\"), "-GamePid", str(OS.get_process_id())]
	if dest != "": args += ["-Dest", dest]
	if Rhythia.has_method("save_settings"): Rhythia.save_settings()
	var pid = OS.execute("powershell.exe", args, false, [], false, true)
	if pid <= 0: return "Couldn't start PowerShell."
	tree.quit()
	return ""

# (no backslashes in here: GDScript would read them as escapes)
const PS = """param([string]$Link, [string]$Dest = '', [string]$Exe = '', [int]$GamePid = 0)
$ErrorActionPreference = 'Stop'
$Host.UI.RawUI.WindowTitle = 'Rhythia-reimagined - moving your user folder'
$sep = [IO.Path]::DirectorySeparatorChar
function Say($t, $c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Norm($p) { [IO.Path]::GetFullPath($p).TrimEnd($sep) }
function Stats($p) {
	$f = @(Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue)
	$b = 0; foreach ($x in $f) { $b += $x.Length }
	[pscustomobject]@{ n = $f.Count; b = [int64]$b }
}
function Gb($b) { '{0:N2} GB' -f ($b / 1GB) }
function Restart-Game { if ($Exe -and (Test-Path -LiteralPath $Exe)) { Start-Process -FilePath $Exe -WorkingDirectory ([IO.Path]::GetDirectoryName($Exe)) } }
function Fail($t) {
	Say ''
	Say $t 'Red'
	Say ''
	Say 'Press Enter to start the game again.'
	[void](Read-Host)
	Restart-Game
	exit 1
}
try {
	Say 'Rhythia-reimagined: moving your user folder' 'Cyan'
	Say 'Waiting for the game to close...'
	if ($GamePid -gt 0) { Wait-Process -Id $GamePid -Timeout 60 -ErrorAction SilentlyContinue }
	Start-Sleep -Seconds 1
	$Link = Norm $Link
	$item = Get-Item -LiteralPath $Link -Force
	$junction = [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
	$from = if ($junction) { Norm (@($item.Target)[0]) } else { $Link }
	$back = [string]::IsNullOrEmpty($Dest)
	if ($back -and -not $junction) { Fail 'Your user folder is already in the default place. Nothing to do.' }
	$copyTo = if ($back) { $Link + '.rr_new' } else { Norm $Dest }
	$a = $from.ToLower() + $sep; $c = $copyTo.ToLower() + $sep
	if ($c.StartsWith($a) -or $a.StartsWith($c)) { Fail 'The new folder cannot be inside the current one (or the other way round). Nothing was changed.' }
	if ((Test-Path -LiteralPath $copyTo) -and @(Get-ChildItem -LiteralPath $copyTo -Force).Count -gt 0) { Fail ('Pick an empty folder: ' + $copyTo + ' has files in it. Nothing was changed.') }
	Say ('From: ' + $from)
	Say ('To:   ' + $(if ($back) { $Link } else { $copyTo }))
	Say 'Counting files...'
	$s = Stats $from
	$free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($copyTo))).AvailableFreeSpace
	Say ('{0} files, {1} ({2} free on the target drive)' -f $s.n, (Gb $s.b), (Gb $free))
	if ($free -lt $s.b + 100MB) { Fail 'Not enough free space on the target drive. Nothing was changed.' }
	Say ''
	Say 'Copying...' 'Cyan'
	& robocopy $from $copyTo /E /COPY:DAT /DCOPY:T /XJ /R:2 /W:1 /NDL /NJH /NP
	$rc = $LASTEXITCODE
	if ($rc -ge 8) { Fail ('The copy failed (robocopy code ' + $rc + '). Your data is untouched in ' + $from + '. The partial copy in ' + $copyTo + ' can be deleted.') }
	$t = Stats $copyTo
	if ($t.n -lt $s.n -or $t.b -lt $s.b) { Fail ('The copy is incomplete ({0} of {1} files). Your data is untouched in {2}.' -f $t.n, $s.n, $from) }
	Say 'Copy checked.' 'Green'
	# switch: the old path becomes a junction to the new folder (or the real folder again)
	$old = $from
	if ($junction) { & cmd /c rmdir "$Link" }
	else {
		$old = $Link + '.rr_old'
		try { Rename-Item -LiteralPath $Link -NewName ([IO.Path]::GetFileName($Link) + '.rr_old') }
		catch { Fail ('Windows would not let go of ' + $Link + ' (is the game or a file in it still open?). Your data is untouched; the copy in ' + $copyTo + ' can be deleted.') }
	}
	if ($back) { Rename-Item -LiteralPath $copyTo -NewName ([IO.Path]::GetFileName($Link)) }
	else {
		& cmd /c mklink /J "$Link" "$copyTo" | Out-Null
		if ($LASTEXITCODE -ne 0) {
			if ($junction) { & cmd /c mklink /J "$Link" "$from" | Out-Null } else { Rename-Item -LiteralPath $old -NewName ([IO.Path]::GetFileName($Link)) }
			Fail 'Could not create the link at the old place. Everything was put back as it was.'
		}
	}
	$marker = Join-Path $(if ($back) { $Link } else { $copyTo }) '.rr_location.txt'
	if ($back) { Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue }
	else { [IO.File]::WriteAllText($marker, $copyTo) }
	Say 'Removing the old copy...'
	& cmd /c rd /s /q "$old"
	if (Test-Path -LiteralPath $old) { Say ('Some old files could not be removed: ' + $old + ' (safe to delete by hand).') 'Yellow' }
	Say ''
	Say 'Done. Starting the game...' 'Green'
	Start-Sleep -Seconds 2
	Restart-Game
} catch { Fail ('Something went wrong: ' + $_.Exception.Message) }
"""
