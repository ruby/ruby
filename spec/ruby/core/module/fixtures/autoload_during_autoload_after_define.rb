module ModuleSpecs::Autoload
  class DuringAutoloadAfterDefine
    block = ScratchPad.recorded
    ScratchPad.record(block.call)
  end
end
