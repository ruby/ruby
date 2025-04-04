class CApiClassSpecs
  module M
    def included?
      true
    end
  end

  class Alloc
    attr_reader :initialized
    attr_reader :arguments

    def initialize(*args)
      @initialized = true
      @arguments   = args
    end
  end

  class KeywordAlloc
    attr_reader :initialized, :args, :kwargs

    def initialize(*args, **kwargs)
      @initialized = true
      @args = args
      @kwargs = kwargs
    end
  end

  class Attr
    def initialize
      @foo, @bar, @baz = 1, 2, 3
    end
  end

  class CVars
    @@cvar  = :cvar
    @c_ivar = :c_ivar

    def new_cv
      @@new_cv if defined? @@new_cv
    end

    def new_cvar
      @@new_cvar if defined? @@new_cvar
    end

    def rbdcv_cvar
      @@rbdcv_cvar if defined? @@rbdcv_cvar
    end
  end

  class Inherited
    def self.inherited(klass)
      klass
    end
  end

  class NewClass
    def self.inherited(klass)
      raise "#{name}.inherited called"
    end
  end

  class Super
    def call_super_method
      :super_method
    end
  end

  class Sub < Super
    def call_super_method
      :subclass_method
    end
  end

  class SubM < Super
    include M
  end

  class SubSub < Sub
    def call_super_method
      :subsubclass_method
    end
  end

  class SuperSelf
    def call_super_method
      self
    end
  end

  class SubSelf < SuperSelf
  end

  class A
    C = 1
    autoload :D, File.expand_path('../path_to_class.rb', __FILE__)

    class B
    end

    module M
    end
  end

  class Callbacks
    def self.inherited(child)
      ScratchPad << [:inherited, child.name, Object.const_source_location(child.name) ? :location : :unknown_location]
    end

    def self.const_added(const_name)
      ScratchPad << [:const_added, const_name, const_source_location(const_name) ? :location : :unknown_location]
    end
  end
end
