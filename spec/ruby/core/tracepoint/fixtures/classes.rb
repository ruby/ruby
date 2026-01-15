module TracePointSpec
  @thread = Thread.current

  def self.target_thread?
    Thread.current == @thread
  end

  class ClassWithMethodAlias
    def m
    end
    alias_method :m_alias, :m
  end

  module A
    def bar; end
  end

  class B
    include A

    def foo; end;
  end

  class C < B
    def initialize
    end

    def foo
      super
    end

    def bar
      super
    end
  end

  def self.test
    'test'
  end
end
