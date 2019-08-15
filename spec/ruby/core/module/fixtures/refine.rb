module ModuleSpecs
  class ClassWithFoo
    def foo; "foo" end
  end

  module PrependedModule
    def foo; "foo from prepended module"; end
  end

  module IncludedModule
    def foo; "foo from included module"; end
  end
end
