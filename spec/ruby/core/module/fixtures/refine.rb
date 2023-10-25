module ModuleSpecs
  class ClassWithFoo
    def foo; "foo" end
  end

  class ClassWithSuperFoo
    def foo; [:C] end
  end

  module PrependedModule
    def foo; "foo from prepended module"; end
  end

  module IncludedModule
    def foo; "foo from included module"; end
  end

  def self.build_refined_class(for_super: false)
    if for_super
      Class.new(ClassWithSuperFoo)
    else
      Class.new(ClassWithFoo)
    end
  end
end
