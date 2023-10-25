# Constant lookup is cached.
assert_equal '1', %q{
  CONST = 1

  def const
    CONST
  end

  const
  const
}

# Invalidate when a constant is set.
assert_equal '2', %q{
  CONST = 1

  def const
    CONST
  end

  const

  CONST = 2

  const
}

# Invalidate when a constant of the same name is set.
assert_equal '1', %q{
  CONST = 1

  def const
    CONST
  end

  const

  class Container
    CONST = 2
  end

  const
}

# Invalidate when a constant is removed.
assert_equal 'missing', %q{
  class Container
    CONST = 1

    def const
      CONST
    end

    def self.const_missing(name)
      'missing'
    end

    new.const
    remove_const :CONST
  end

  Container.new.const
}

# Invalidate when a constant's visibility changes.
assert_equal 'missing', %q{
  class Container
    CONST = 1

    def self.const_missing(name)
      'missing'
    end
  end

  def const
    Container::CONST
  end

  const

  Container.private_constant :CONST

  const
}

# Invalidate when a constant's visibility changes even if the call to the
# visibility change method fails.
assert_equal 'missing', %q{
  class Container
    CONST1 = 1

    def self.const_missing(name)
      'missing'
    end
  end

  def const1
    Container::CONST1
  end

  const1

  begin
    Container.private_constant :CONST1, :CONST2
  rescue NameError
  end

  const1
}

# Invalidate when a module is included.
assert_equal 'INCLUDE', %q{
  module Include
    CONST = :INCLUDE
  end

  class Parent
    CONST = :PARENT
  end

  class Child < Parent
    def const
      CONST
    end

    new.const

    include Include
  end

  Child.new.const
}

# Invalidate when const_missing is hit.
assert_equal '2', %q{
  module Container
    Foo = 1
    Bar = 2

    class << self
      attr_accessor :count

      def const_missing(name)
        @count += 1
        @count == 1 ? Foo : Bar
      end
    end

    @count = 0
  end

  def const
    Container::Baz
  end

  const
  const
}

# Invalidate when the iseq gets cleaned up.
assert_equal '2', %q{
  CONSTANT = 1

  iseq = RubyVM::InstructionSequence.compile(<<~RUBY)
    CONSTANT
  RUBY

  iseq.eval
  iseq = nil

  GC.start
  CONSTANT = 2
}

# Invalidate when the iseq gets cleaned up even if it was never in the cache.
assert_equal '2', %q{
  CONSTANT = 1

  iseq = RubyVM::InstructionSequence.compile(<<~RUBY)
    CONSTANT
  RUBY

  iseq = nil

  GC.start
  CONSTANT = 2
}
