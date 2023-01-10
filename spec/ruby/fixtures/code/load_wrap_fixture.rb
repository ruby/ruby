class LoadSpecWrap
  ScratchPad << String
end

LOAD_WRAP_SPECS_TOP_LEVEL_CONSTANT = 1

def load_wrap_specs_top_level_method
  :load_wrap_specs_top_level_method
end
ScratchPad << method(:load_wrap_specs_top_level_method).owner

ScratchPad << self
