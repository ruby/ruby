ScratchPad << :nested_loaded

module ModuleSpecs::Autoload
  class SatisfiedByRequireNested
    autoload :Inner, File.expand_path("autoload_satisfied_by_require_nested_inner.rb", __dir__)
  end
end
