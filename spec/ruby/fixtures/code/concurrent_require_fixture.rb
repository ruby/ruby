object = ScratchPad.recorded
thread = Thread.new { object.require(__FILE__) }
Thread.pass until thread.stop?
ScratchPad.record(thread)
