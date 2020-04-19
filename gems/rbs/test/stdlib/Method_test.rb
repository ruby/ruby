require_relative "test_helper"

class MethodTest < StdlibTest
  target Method
  using hook.refinement

  class Foo
    def foo
    end

    def foo_with_args(*, **)
    end

    def foo_with_many_args(x, y=42, *other, k_x:, k_y: 42, **k_other, &b)
    end

    def foo_with_arg_and_rest(x, *)
    end
  end

  class Bar < Foo
    def foo
    end
  end

  def test_to_proc
    Foo.new.method(:foo).to_proc
  end

  def test_call
    Foo.new.method(:foo).call
    Foo.new.method(:foo_with_args).call(1)
  end

  def test_lshift
    f = Foo.new.method(:foo_with_args)
    g = proc { }
    f << g
  end

  def test_triple_equal
    f = Foo.new.method(:foo_with_args)
    f === 1
  end

  def test_rshift
    f = Foo.new.method(:foo_with_args)
    g = proc { }
    f >> g
  end

  def test_square_bracket
    Foo.new.method(:foo_with_args)[1]
  end

  def test_arity
    Foo.new.method(:foo_with_args).arity
  end

  def test_clone
    Foo.new.method(:foo_with_args).clone
  end

  def test_curry
    f = Foo.new.method(:foo)
    f.curry
    f.curry(0)
  end

  def test_original_name
    Foo.new.method(:foo).original_name
  end

  def test_parameters
    Foo.new.method(:foo).parameters
    Foo.new.method(:foo_with_args).parameters
    Foo.new.method(:foo_with_many_args).parameters
    Foo.new.method(:foo_with_arg_and_rest).parameters
  end

  def test_receiver
    Foo.new.method(:foo).receiver
  end

  def test_source_location
    Foo.new.method(:foo).source_location
    method(:puts).source_location
  end

  def test_super_method
    Foo.new.method(:foo).super_method
    Bar.new.method(:foo).super_method
  end
end
