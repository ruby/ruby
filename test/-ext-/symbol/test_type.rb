require 'test/unit'
require "-test-/symbol"

module Test_Symbol
  class TestType < Test::Unit::TestCase
    def assert_symtype(sym, pred, msg = nil)
      assert_send([Bug::Symbol, pred, sym], msg)
    end

    def assert_not_symtype(sym, pred, msg = nil)
      assert_not_send([Bug::Symbol, pred, sym], msg)
    end

    def test_const
      assert_symtype("Foo", :const?)
      assert_not_symtype("F!", :const?)
      assert_not_symtype("foo", :const?)
      assert_not_symtype("@foo", :const?)
      assert_not_symtype("@@foo", :const?)
      assert_not_symtype("$foo", :const?)
      assert_not_symtype("foo=", :const?)
      assert_not_symtype("[foo]", :const?)
      assert_not_symtype("xFoo", :const?)
    end

    def test_local
      assert_symtype("foo", :local?)
      assert_symtype("fooBar", :local?)
      assert_symtype("foo_bar", :local?)
      assert_not_symtype("foo!", :local?)
      assert_not_symtype("foo?", :local?)
      assert_not_symtype("Foo", :local?)
      assert_not_symtype("@foo", :local?)
      assert_not_symtype("@@foo", :local?)
      assert_not_symtype("$foo", :local?)
      assert_not_symtype("foo=", :local?)
      assert_not_symtype("[foo]", :local?)
    end

    def test_global
      assert_symtype("$foo", :global?)
      assert_symtype("$$", :global?)
      assert_not_symtype("$()", :global?)
      assert_not_symtype("$", :global?)
      assert_not_symtype("foo", :global?)
      assert_not_symtype("Foo", :global?)
      assert_not_symtype("@foo", :global?)
      assert_not_symtype("@@foo", :global?)
      assert_not_symtype("foo=", :global?)
      assert_not_symtype("[foo]", :global?)
    end

    def test_instance
      assert_symtype("@foo", :instance?)
      assert_not_symtype("@", :instance?)
      assert_not_symtype("@1", :instance?)
      assert_not_symtype("@@", :instance?)
      assert_not_symtype("foo", :instance?)
      assert_not_symtype("Foo", :instance?)
      assert_not_symtype("@@foo", :instance?)
      assert_not_symtype("$foo", :instance?)
      assert_not_symtype("foo=", :instance?)
      assert_not_symtype("[foo]", :instance?)
    end

    def test_class
      assert_symtype("@@foo", :class?)
      assert_not_symtype("@@", :class?)
      assert_not_symtype("@", :class?)
      assert_not_symtype("@@1", :class?)
      assert_not_symtype("foo", :class?)
      assert_not_symtype("Foo", :class?)
      assert_not_symtype("@foo", :class?)
      assert_not_symtype("$foo", :class?)
      assert_not_symtype("foo=", :class?)
      assert_not_symtype("[foo]", :class?)
    end

    def test_attrset
      assert_symtype("foo=", :attrset?)
      assert_symtype("Foo=", :attrset?)
      assert_symtype("@foo=", :attrset?)
      assert_symtype("@@foo=", :attrset?)
      assert_symtype("$foo=", :attrset?)
      assert_symtype("0=", :attrset?)
      assert_symtype("@=", :attrset?)
      assert_symtype("@@=", :attrset?)
      assert_not_symtype("foo", :attrset?)
      assert_not_symtype("Foo", :attrset?)
      assert_not_symtype("@foo", :attrset?)
      assert_not_symtype("@@foo", :attrset?)
      assert_not_symtype("$foo", :attrset?)
      assert_not_symtype("[foo]", :attrset?)
      assert_symtype("[foo]=", :attrset?)
      assert_equal(:"foo=", Bug::Symbol.attrset("foo"))
      assert_symtype(Bug::Symbol.attrset("foo"), :attrset?)
      assert_equal(:"Foo=", Bug::Symbol.attrset("Foo"))
      assert_symtype(Bug::Symbol.attrset("Foo"), :attrset?)
      assert_equal(:"@foo=", Bug::Symbol.attrset("@foo"))
      assert_symtype(Bug::Symbol.attrset("@foo"), :attrset?)
      assert_equal(:"@@foo=", Bug::Symbol.attrset("@@foo"))
      assert_symtype(Bug::Symbol.attrset("@@foo"), :attrset?)
      assert_equal(:"$foo=", Bug::Symbol.attrset("$foo"))
      assert_symtype(Bug::Symbol.attrset("$foo"), :attrset?)
      assert_equal(:"[foo]=", Bug::Symbol.attrset("[foo]"))
      assert_symtype(Bug::Symbol.attrset("[foo]"), :attrset?)
      assert_equal(:[]=, Bug::Symbol.attrset(:[]))
      assert_symtype(Bug::Symbol.attrset("foo?="), :attrset?)
      assert_equal(:"foo?=", Bug::Symbol.attrset(:foo?))
      assert_symtype(Bug::Symbol.attrset("foo!="), :attrset?)
      assert_equal(:"foo!=", Bug::Symbol.attrset(:foo!))
    end
  end
end
