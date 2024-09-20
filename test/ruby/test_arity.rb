# frozen_string_literal: false
require 'test/unit'

class TestArity < Test::Unit::TestCase
  def assert_arity(expected, method_proc = nil, argc = 0)
    args = (1..argc).to_a
    assert_raise_with_message(ArgumentError, /wrong number of arguments \(.*\b(\d+)\b.* (\d\S*?)\)/) do
      case method_proc
      when nil
        yield
      when Symbol
        method(method_proc).call(*args)
      else
        method_proc.call(*args)
      end
    end
    assert_equal expected, [$1, $2]
  end

  def a
  end

  def b(a, b, c, d=1, e=2, f, g, h, i, &block)
  end

  def c(a, b, c, d=1, e=2, *rest)
  end

  def d(a, b: 42)
  end

  def e(a, b:42, **c)
  end

  def f(a, b, c=1, *rest, d: 3)
  end

  def test_method_err_mess
    assert_arity(%w[1 0],     :a, 1)
    assert_arity(%w[10 7..9], :b, 10)
    assert_arity(%w[2 3+],    :c, 2)
    assert_arity(%w[2 1],     :d, 2)
    assert_arity(%w[0 1],     :d, 0)
    assert_arity(%w[2 1],     :e, 2)
    assert_arity(%w[0 1],     :e, 0)
    assert_arity(%w[1 2+],    :f, 1)
  end

  def test_proc_err_mess
    assert_arity(%w[0 1..2],  ->(b, c=42){}, 0)
    assert_arity(%w[1 2+],    ->(a, b, c=42, *d){}, 1)
    assert_arity(%w[3 4+],    ->(a, b, *c, d, e){}, 3)
    assert_arity(%w[3 1..2],  ->(b, c=42){}, 3)
    assert_arity(%w[1 0],     ->(&block){}, 1)
    # Double checking:
    p = Proc.new{|b, c=42| :ok}
    assert_equal :ok,  p.call(1, 2, 3)
    assert_equal :ok,  p.call
  end

  def test_message_change_issue_6085
    assert_arity(%w[3 1..2])  { SignalException.new(1, "", nil) }
    assert_arity(%w[1 0])     { Hash.new(1){} }
    assert_arity(%w[3 1..2])  { Module.send :define_method, 1, 2, 3 }
    assert_arity(%w[1 2])     { "".sub!(//) }
    assert_arity(%w[0 1..2])  { "".sub!{} }
    assert_arity(%w[0 1+])    { exec }
  end
end
