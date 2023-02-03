class CApiObjectSpecs
  class IVars
    def initialize
      @a = 3
      @b = 7
      @c = 4
    end

    def self.set_class_variables
      @@foo = :a
      @@bar = :b
      @@baz = :c
    end
  end

  module MVars
    @@mvar = :foo
    @@mvar2 = :bar

    @ivar = :baz
  end

  module CVars
    @@cvar = :foo
    @@cvar2 = :bar

    @ivar = :baz
  end
end
