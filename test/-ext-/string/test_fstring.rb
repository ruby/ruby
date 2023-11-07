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

  def test_rb_enc_interned_str_autoloaded_encoding
    assert_separately([], <<~RUBY)
      require '-test-/string'
      assert_include(Encoding::Windows_31J.inspect, 'autoload')
      Bug::String.rb_enc_interned_str(Encoding::Windows_31J)
    RUBY
  end

  def test_rb_enc_str_new_autoloaded_encoding
    assert_separately([], <<~RUBY)
      require '-test-/string'
      assert_include(Encoding::Windows_31J.inspect, 'autoload')
      Bug::String.rb_enc_str_new(Encoding::Windows_31J)
    RUBY
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

  def test_fake_str
    assert_equal([*"a".."z"].join(""), Bug::String.fstring_fake_str)
  end

  class S < String
  end

  def test_subclass
    str = S.new(__method__.to_s * 3)
    str.freeze
    assert_fstring(str) {|s| assert_instance_of(S, s)}
  end
end
