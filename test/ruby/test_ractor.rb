# frozen_string_literal: false
require 'test/unit'

class TestRactor < Test::Unit::TestCase
  def test_shareability_of_iseq_proc
    y = nil.instance_eval do
      foo = []
      proc { foo }
    end
    assert_unshareable(y, /unshareable object \[\] from variable 'foo'/)

    y = [].instance_eval { proc { self } }
    assert_unshareable(y, /Proc's self is not shareable/)

    y = [].freeze.instance_eval { proc { self } }
    assert_make_shareable(y)
  end

  def test_shareability_of_curried_proc
    x = nil.instance_eval do
      foo = []
      proc { foo }.curry
    end
    assert_unshareable(x, /unshareable object \[\] from variable 'foo'/)

    x = nil.instance_eval do
      foo = 123
      proc { foo }.curry
    end
    assert_make_shareable(x)
  end

  def test_shareability_of_method_proc
    str = +""

    x = str.instance_exec { proc { to_s } }
    assert_unshareable(x, /Proc's self is not shareable/)

    x = str.instance_exec { method(:to_s) }
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)

    x = str.instance_exec { method(:to_s).to_proc }
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)

    x = str.instance_exec { method(:itself).to_proc }
    assert_unshareable(x, "can not make shareable object for #<Method: String(Kernel)#itself()>", exception: Ractor::Error)

    str.freeze

    x = str.instance_exec { proc { to_s } }
    assert_make_shareable(x)

    x = str.instance_exec { method(:to_s) }
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)

    x = str.instance_exec { method(:to_s).to_proc }
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)

    x = str.instance_exec { method(:itself).to_proc }
    assert_unshareable(x, "can not make shareable object for #<Method: String(Kernel)#itself()>", exception: Ractor::Error)
  end

  def assert_make_shareable(obj)
    refute Ractor.shareable?(obj), "object was already shareable"
    Ractor.make_shareable(obj)
    assert Ractor.shareable?(obj), "object didn't become shareable"
  end

  def assert_unshareable(obj, msg=nil, exception: Ractor::IsolationError)
    refute Ractor.shareable?(obj), "object is already shareable"
    assert_raise_with_message(exception, msg) do
      Ractor.make_shareable(obj)
    end
    refute Ractor.shareable?(obj), "despite raising, object became shareable"
  end
end
