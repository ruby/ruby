module ModuleSpecs::Autoload
  autoload(:AutoloadCurrentFile, __FILE__)

  ScratchPad.record autoload?(:AutoloadCurrentFile)
end
