action = ScratchPad.recorded.pop
ScratchPad << __FILE__
action.call if action
ScratchPad << caller_locations(0)[0].absolute_path
