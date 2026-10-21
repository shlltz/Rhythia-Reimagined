extends Node
# The few game globals the tested scripts name (Updater.gd notifies); prints instead of showing.
const NOTIFY_INFO = 0
const NOTIFY_SUCCEED = 1
const NOTIFY_WARN = 2
const NOTIFY_ERROR = 3

func notify(kind:int, text:String, title:String = ""):
	print("  (notify %d: %s - %s)" % [kind, title, text])
