block = ScratchPad.recorded
ScratchPad.record(block.call)

module ModuleSpecs::Autoload
  class DuringAutoload
  end
end
