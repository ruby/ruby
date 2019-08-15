# frozen_string_literal: false
require 'test/unit'
require '-test-/string'
require_relative '../symbol/noninterned_name'

class Test_String_Fstring < Test::Unit::TestCase
  include Test_Symbol::NonInterned

  def assert_fstring(str)
    fstr = Bug::String.fstring(str)
    yield str
    yield fstr
  end

  def test_taint_shared_string
    str = __method__.to_s.dup
    str.taint
    assert_fstring(str) {|s| assert_predicate(s, :tainted?)}
  end

  def test_taint_normal_string
    str = __method__.to_s * 3
    str.taint
    assert_fstring(str) {|s| assert_predicate(s, :tainted?)}
  end

  def test_taint_registered_tainted
    str = __method__.to_s * 3
    str.taint
    assert_fstring(str) {|s| assert_predicate(s, :tainted?)}

    str = __method__.to_s * 3
    assert_fstring(str) {|s| assert_not_predicate(s, :tainted?)}
  end

  def test_taint_registered_untainted
    str = __method__.to_s * 3
    assert_fstring(str) {|s| assert_not_predicate(s, :tainted?)}

    str = __method__.to_s * 3
    str.taint
    assert_fstring(str) {|s| assert_predicate(s, :tainted?)}
  end

  def test_instance_variable
    str = __method__.to_s * 3
    str.instance_variable_set(:@test, 42)
    str.freeze
    assert_fstring(str) {|s| assert_send([s, :instance_variable_defined?, :@test])}
  end

  def test_singleton_method
    str = __method__.to_s * 3
    def str.foo
    end
    str.freeze
    assert_fstring(str) {|s| assert_send([s, :respond_to?, :foo])}
  end

  def test_singleton_class
    str = noninterned_name
    fstr = Bug::String.fstring(str)
    assert_raise(TypeError) {fstr.singleton_class}
  end

  class S < String
  end

  def test_subclass
    str = S.new(__method__.to_s * 3)
    str.freeze
    assert_fstring(str) {|s| assert_instance_of(S, s)}
  end
end
