extends Node
# Audio output latency the engine reports (mix buffer + driver), for the project's audio/output_latency.
# Output @@OUT@@/audiolat.txt
func _ready():
	call_deferred("run")
func run():
	yield(get_tree().create_timer(3.0), "timeout")
	var f = File.new()
	f.open("@@OUT@@/audiolat.txt", File.WRITE)
	f.store_line("output_latency setting %s ms, mix rate %d, reported latency %.1f ms, driver %s" % [str(ProjectSettings.get_setting("audio/output_latency")), AudioServer.get_mix_rate(), AudioServer.get_output_latency() * 1000.0, OS.get_audio_driver_name(OS.get_current_audio_driver()) if OS.has_method("get_audio_driver_name") else "?"])
	f.close()
	OS.kill(OS.get_process_id())
