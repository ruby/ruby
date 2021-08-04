# encoding: UTF-8
# frozen_string_literal: true
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

    # 'y' and 'n' are kind of ambiguous.  Syck treated y and n literals in
    # YAML documents as strings.  But this is not what the YAML 1.1 spec says.
    # YAML 1.1 says they should be treated as booleans.  When we're dumping
    # documents, we know it's a string, so adding quotes will eliminate the
    # "ambiguity" in the emitted document
    def test_y_is_quoted
      assert_match(/"y"/, Psych.dump("y"))
    end

    def test_n_is_quoted
      assert_match(/"n"/, Psych.dump("n"))
    end

    def test_string_with_newline
      assert_equal "1\n2", Psych.load("--- ! '1\n\n  2'\n")
    end

    def test_no_doublequotes_with_special_characters
      assert_equal 2, Psych.dump(%Q{<%= ENV["PATH"] %>}).count('"')
    end

    def test_no_quotes_when_start_with_non_ascii_character
      yaml = Psych.dump 'Český non-ASCII'.encode(Encoding::UTF_8)
      assert_match(/---\s*[^"'!]+$/, yaml)
    end

    def test_doublequotes_when_there_is_a_single
      str = "@123'abc"
      yaml = Psych.dump str
      assert_match(/---\s*"/, yaml)
      assert_equal str, Psych.load(yaml)
    end

    def test_plain_when_shorten_than_line_width_and_no_final_line_break
      str = "Lorem ipsum"
      yaml = Psych.dump str, line_width: 12
      assert_match(/---\s*[^>|]+\n/, yaml)
      assert_equal str, Psych.load(yaml)
    end

    def test_plain_when_shorten_than_line_width_and_with_final_line_break
      str = "Lorem ipsum\n"
      yaml = Psych.dump str, line_width: 12
      assert_match(/---\s*[^>|]+\n/, yaml)
      assert_equal str, Psych.load(yaml)
    end

    def test_folded_when_longer_than_line_width_and_with_final_line_break
      str = "Lorem ipsum dolor sit\n"
      yaml = Psych.dump str, line_width: 12
      assert_match(/---\s*>\n(.*\n){2}\Z/, yaml)
      assert_equal str, Psych.load(yaml)
    end

    # http://yaml.org/spec/1.2/2009-07-21/spec.html#id2593651
    def test_folded_strip_when_longer_than_line_width_and_no_newlines
      str = "Lorem ipsum dolor sit amet, consectetur"
      yaml = Psych.dump str, line_width: 12
      assert_match(/---\s*>-\n(.*\n){3}\Z/, yaml)
      assert_equal str, Psych.load(yaml)
    end

    def test_literal_when_inner_and_final_line_break
      [
        "Lorem ipsum\ndolor\n",
        "Lorem ipsum\nZolor\n",
      ].each do |str|
        yaml = Psych.dump str, line_width: 12
        assert_match(/---\s*\|\n(.*\n){2}\Z/, yaml)
        assert_equal str, Psych.load(yaml)
      end
    end

    # http://yaml.org/spec/1.2/2009-07-21/spec.html#id2593651
    def test_literal_strip_when_inner_line_break_and_no_final_line_break
      [
        "Lorem ipsum\ndolor",
        "Lorem ipsum\nZolor",
      ].each do |str|
        yaml = Psych.dump str, line_width: 12
        assert_match(/---\s*\|-\n(.*\n){2}\Z/, yaml)
        assert_equal str, Psych.load(yaml)
      end
    end

    def test_cycle_x
      str = X.new 'abc'
      assert_cycle str
    end

    def test_dash_dot
      assert_cycle '-.'
      assert_cycle '+.'
    end

    def test_float_with_no_fractional_before_exponent
      assert_cycle '0.E+0'
    end

    def test_string_subclass_with_anchor
      y = Psych.unsafe_load <<-eoyml
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
      y = Psych.unsafe_load <<-eoyml
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
      y = Psych.unsafe_load Psych.dump Y.new("foo").tap {|o| o.val = 1}
      assert_equal "foo", y
      assert_equal Y, y.class
      assert_equal 1, y.val
    end

    def test_backwards_with_syck
      x = Psych.unsafe_load "--- !str:#{X.name} foo\n\n"
      assert_equal X, x.class
      assert_equal 'foo', x
    end

    def test_empty_subclass
      assert_match "!ruby/string:#{X}", Psych.dump(X.new)
      x = Psych.unsafe_load Psych.dump X.new
      assert_equal X, x.class
    end

    def test_empty_character_subclass
      assert_match "!ruby/string:#{Z}", Psych.dump(Z.new)
      x = Psych.unsafe_load Psych.dump Z.new
      assert_equal Z, x.class
    end

    def test_subclass_with_attributes
      y = Psych.unsafe_load Psych.dump Y.new.tap {|o| o.val = 1}
      assert_equal Y, y.class
      assert_equal 1, y.val
    end

    def test_string_with_base_60
      yaml = Psych.dump '01:03:05'
      assert_match "'01:03:05'", yaml
      assert_equal '01:03:05', Psych.load(yaml)
    end

    def test_nonascii_string_as_binary
      string = "hello \x80 world!".dup
      string.force_encoding 'ascii-8bit'
      yml = Psych.dump string
      assert_match(/binary/, yml)
      assert_equal string, Psych.load(yml)
    end

    def test_binary_string_null
      string = "\x00\x92".b
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

    def test_ascii_only_binary_string
      string = "non bnry string".b
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
      food = "is delicious".dup
      ivar = "on rock and roll"
      food.instance_variable_set(:@we_built_this_city, ivar)

      Psych.load Psych.dump food
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
      string = ''.b
      (percentage * length).to_i.times do |i|
        string << "\x92".b
      end
      string << 'a' * (length - string.length)
      string
    end
  end
end
