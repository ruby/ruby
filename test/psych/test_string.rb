require_relative 'helper'

module Psych
  class TestString < TestCase
    class X < String
    end

    class Y < String
      attr_accessor :val
    end

    class Z < String
      def initialize
        force_encoding Encoding::US_ASCII
      end
    end

    def test_no_doublequotes_with_special_characters
      assert_equal 2, Psych.dump(%Q{<%= ENV["PATH"] %>}).count('"')
    end

    def test_doublequotes_when_there_is_a_single
      yaml = Psych.dump "@123'abc"
      assert_match(/---\s*"/, yaml)
    end

    def test_cycle_x
      str = X.new 'abc'
      assert_cycle str
    end

    def test_dash_dot
      assert_cycle '-.'
      assert_cycle '+.'
    end

    def test_string_subclass_with_anchor
      y = Psych.load <<-eoyml
---
body:
  string: &70121654388580 !ruby/string
    str: ! 'foo'
  x:
    body: *70121654388580
      eoyml
      assert_equal({"body"=>{"string"=>"foo", "x"=>{"body"=>"foo"}}}, y)
    end

    def test_self_referential_string
      y = Psych.load <<-eoyml
---
string: &70121654388580 !ruby/string
  str: ! 'foo'
  body: *70121654388580
      eoyml

      assert_equal({"string"=>"foo"}, y)
      value = y['string']
      assert_equal value, value.instance_variable_get(:@body)
    end

    def test_another_subclass_with_attributes
      y = Psych.load Psych.dump Y.new("foo").tap {|y| y.val = 1}
      assert_equal "foo", y
      assert_equal Y, y.class
      assert_equal 1, y.val
    end

    def test_backwards_with_syck
      x = Psych.load "--- !str:#{X.name} foo\n\n"
      assert_equal X, x.class
      assert_equal 'foo', x
    end

    def test_empty_subclass
      assert_match "!ruby/string:#{X}", Psych.dump(X.new)
      x = Psych.load Psych.dump X.new
      assert_equal X, x.class
    end

    def test_empty_character_subclass
      assert_match "!ruby/string:#{Z}", Psych.dump(Z.new)
      x = Psych.load Psych.dump Z.new
      assert_equal Z, x.class
    end

    def test_subclass_with_attributes
      y = Psych.load Psych.dump Y.new.tap {|y| y.val = 1}
      assert_equal Y, y.class
      assert_equal 1, y.val
    end

    def test_string_with_base_60
      yaml = Psych.dump '01:03:05'
      assert_match "'01:03:05'", yaml
      assert_equal '01:03:05', Psych.load(yaml)
    end

    def test_nonascii_string_as_binary
      string = "hello \x80 world!"
      string.force_encoding 'ascii-8bit'
      yml = Psych.dump string
      assert_match(/binary/, yml)
      assert_equal string, Psych.load(yml)
    end

    def test_binary_string_null
      string = "\x00"
      yml = Psych.dump string
      assert_match(/binary/, yml)
      assert_equal string, Psych.load(yml)
    end

    def test_binary_string
      string = binary_string
      yml = Psych.dump string
      assert_match(/binary/, yml)
      assert_equal string, Psych.load(yml)
    end

    def test_non_binary_string
      string = binary_string(0.29)
      yml = Psych.dump string
      refute_match(/binary/, yml)
      assert_equal string, Psych.load(yml)
    end

    def test_ascii_only_8bit_string
      string = "abc".encode(Encoding::ASCII_8BIT)
      yml = Psych.dump string
      refute_match(/binary/, yml)
      assert_equal string, Psych.load(yml)
    end

    def test_string_with_ivars
      food = "is delicious"
      ivar = "on rock and roll"
      food.instance_variable_set(:@we_built_this_city, ivar)

      str = Psych.load Psych.dump food
      assert_equal ivar, food.instance_variable_get(:@we_built_this_city)
    end

    def test_binary
      string = [0, 123,22, 44, 9, 32, 34, 39].pack('C*')
      assert_cycle string
    end

    def test_float_confusion
      assert_cycle '1.'
    end

    def binary_string percentage = 0.31, length = 100
      string = ''
      (percentage * length).to_i.times do |i|
        string << "\b"
      end
      string << 'a' * (length - string.length)
      string
    end
  end
end
