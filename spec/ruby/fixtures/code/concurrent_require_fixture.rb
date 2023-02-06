object = ScratchPad.recorded
thread = Thread.new { object.require(__FILE__) }
thread.wakeup unless thread.stop?
ScratchPad.record(thread)
