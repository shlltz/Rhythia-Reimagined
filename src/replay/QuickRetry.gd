extends CanvasLayer
# osu!-style quick retry (Rhythia-reimagined): hold ` (the key left of 1) during a run - the screen
# fades to black and the map restarts once it is black, the same restart as Retry in the pause
# menu (the run isn't recorded). Let go early and it fades back. Live runs only: not in replays,
# not while paused or counting back in, not once the map is ending. Added by NoteManager.

const HOLD = 0.45     # seconds held until the restart
const KEY = KEY_QUOTELEFT

var nm:Node           # NoteManager
var t:float = 0.0
var fade:ColorRect
var done:bool = false

func _ready():
	layer = 70
	nm = get_parent()
	fade = ColorRect.new()
	fade.anchor_right = 1
	fade.anchor_bottom = 1
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.color = Color(0, 0, 0, 0)
	fade.visible = false
	add_child(fade)

func _live() -> bool:
	return !Rhythia.replaying and nm.pause_state == 0 and !nm.get_parent().ending

func _process(delta):
	if done: return
	var held = Input.is_key_pressed(KEY) and _live()
	t = min(t + delta, HOLD) if held else max(t - delta * 3.0, 0.0)
	fade.visible = t > 0.0
	fade.color.a = t / HOLD
	if held and t >= HOLD:
		done = true
		get_tree().change_scene("res://scenes/song.tscn")
