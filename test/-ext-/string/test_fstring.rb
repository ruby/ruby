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

  def test_shared_string_safety
    _unused = -('a' * 30).force_encoding(Encoding::ASCII)
    begin
      verbose_back, $VERBOSE = $VERBOSE, nil
      str = ('a' * 30).force_encoding(Encoding::ASCII).taint
    ensure
      $VERBOSE = verbose_back
    end
    frozen_str = Bug::String.rb_str_new_frozen(str)
    assert_fstring(frozen_str) {|s| assert_equal(str, s)}
    GC.start
    assert_equal('a' * 30, str, "[Bug #16151]")
  end
end
