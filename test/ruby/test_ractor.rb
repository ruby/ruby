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

  def test_shareability_error_uses_inspect
    x = (+"").instance_exec { method(:to_s) }
    def x.to_s
      raise "this should not be called"
    end
    assert_unshareable(x, "can not make shareable object for #<Method: String#to_s()>", exception: Ractor::Error)
  end

  def test_default_thread_group
    assert_separately([], "#{<<~"begin;"}\n#{<<~'end;'}")
    begin;
      Warning[:experimental] = false

      main_ractor_id = Thread.current.group.object_id
      ractor_id = Ractor.new { Thread.current.group.object_id }.value
      refute_equal main_ractor_id, ractor_id
    end;
  end

  def test_class_instance_variables
    assert_ractor(<<~'RUBY')
      # Once we're in multi-ractor mode, the codepaths
      # for class instance variables are a bit different.
      Ractor.new {}.value

      class TestClass
        @a = 1
        @b = 2
        @c = 3
        @d = 4
      end

      assert_equal 4, TestClass.remove_instance_variable(:@d)
      assert_nil TestClass.instance_variable_get(:@d)
      assert_equal 4, TestClass.instance_variable_set(:@d, 4)
      assert_equal 4, TestClass.instance_variable_get(:@d)
    RUBY
  end

  def test_struct_instance_variables
    assert_ractor(<<~'RUBY')
      StructIvar = Struct.new(:member) do
        def initialize(*)
          super
          @ivar = "ivar"
        end
        attr_reader :ivar
      end
      obj = StructIvar.new("member")
      obj_copy = Ractor.new { Ractor.receive }.send(obj).value
      assert_equal obj.ivar, obj_copy.ivar
      refute_same obj.ivar, obj_copy.ivar
      assert_equal obj.member, obj_copy.member
      refute_same obj.member, obj_copy.member
    RUBY
  end

  def test_fork_raise_isolation_error
    assert_ractor(<<~'RUBY')
      ractor = Ractor.new do
        Process.fork
      rescue Ractor::IsolationError => e
        e
      end
      assert_equal Ractor::IsolationError, ractor.value.class
    RUBY
  end if Process.respond_to?(:fork)

  def test_require_raises_and_no_ractor_belonging_issue
    assert_ractor(<<~'RUBY')
      require "tempfile"
      f = Tempfile.new(["file_to_require_from_ractor", ".rb"])
      f.write("raise 'uh oh'")
      f.flush
      err_msg = Ractor.new(f.path) do |path|
        begin
          require path
        rescue RuntimeError => e
          e.message # had confirm belonging issue here
        else
          nil
        end
      end.value
      assert_equal "uh oh", err_msg
    RUBY
  end

  def test_require_non_string
    assert_ractor(<<~'RUBY')
      require "tempfile"
      require "pathname"
      f = Tempfile.new(["file_to_require_from_ractor", ".rb"])
      f.write("")
      f.flush
      result = Ractor.new(f.path) do |path|
        require Pathname.new(path)
        "success"
      end.value
      assert_equal "success", result
    RUBY
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
