require 'test/unit'

class TestAlias < Test::Unit::TestCase
  class Alias0
    def foo; "foo" end
  end
  class Alias1<Alias0
    alias bar foo
    def foo; "foo+" + super end
  end
  class Alias2<Alias1
    alias baz foo
    undef foo
  end
  class Alias3<Alias2
    def foo
      defined? super
    end
    def bar
      defined? super
    end
    def quux
      defined? super
    end
  end

  def test_alias
    x = Alias2.new
    assert_equal("foo", x.bar)
    assert_equal("foo+foo", x.baz)

    # test_check for cache
    assert_equal("foo+foo", x.baz)

    x = Alias3.new
    assert(!x.foo)
    assert(x.bar)
    assert(!x.quux)
  end
end
