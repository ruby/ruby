# encoding: utf-8
# frozen_string_literal: false
require 'test_helper'
require 'stringio'
require 'tempfile'
require 'ostruct'
require 'bigdecimal'

class JSONParserTest < Test::Unit::TestCase
  include JSON

  def test_construction
    parser = JSON::Parser.new('test')
    assert_equal 'test', parser.source
  end

  def test_argument_encoding
    source = "{}".encode("UTF-16")
    JSON::Parser.new(source)
    assert_equal Encoding::UTF_16, source.encoding
  end if defined?(Encoding::UTF_16)

  def test_error_message_encoding
    bug10705 = '[ruby-core:67386] [Bug #10705]'
    json = ".\"\xE2\x88\x9A\"".force_encoding(Encoding::UTF_8)
    e = assert_raise(JSON::ParserError) {
      JSON::Ext::Parser.new(json).parse
    }
    assert_equal(Encoding::UTF_8, e.message.encoding, bug10705)
    assert_include(e.message, json, bug10705)
  end if defined?(Encoding::UTF_8) and defined?(JSON::Ext::Parser)

  def test_parsing
    parser = JSON::Parser.new('"test"')
    assert_equal 'test', parser.parse
  end

  def test_parser_reset
    parser = Parser.new('{"a":"b"}')
    assert_equal({ 'a' => 'b' }, parser.parse)
    assert_equal({ 'a' => 'b' }, parser.parse)
  end

  def test_parse_values
    assert_equal(nil,      parse('null'))
    assert_equal(false,    parse('false'))
    assert_equal(true,     parse('true'))
    assert_equal(-23,      parse('-23'))
    assert_equal(23,       parse('23'))
    assert_in_delta(0.23,  parse('0.23'), 1e-2)
    assert_in_delta(0.0,   parse('0e0'), 1e-2)
    assert_equal("",       parse('""'))
    assert_equal("foobar", parse('"foobar"'))
  end

  def test_parse_simple_arrays
    assert_equal([],             parse('[]'))
    assert_equal([],             parse('  [  ] '))
    assert_equal([ nil ],        parse('[null]'))
    assert_equal([ false ],      parse('[false]'))
    assert_equal([ true ],       parse('[true]'))
    assert_equal([ -23 ],        parse('[-23]'))
    assert_equal([ 23 ],         parse('[23]'))
    assert_equal_float([ 0.23 ], parse('[0.23]'))
    assert_equal_float([ 0.0 ],  parse('[0e0]'))
    assert_equal([""],           parse('[""]'))
    assert_equal(["foobar"],     parse('["foobar"]'))
    assert_equal([{}],           parse('[{}]'))
  end

  def test_parse_simple_objects
    assert_equal({}, parse('{}'))
    assert_equal({}, parse(' {   }   '))
    assert_equal({ "a" => nil }, parse('{   "a"   :  null}'))
    assert_equal({ "a" => nil }, parse('{"a":null}'))
    assert_equal({ "a" => false }, parse('{   "a"  :  false  }  '))
    assert_equal({ "a" => false }, parse('{"a":false}'))
    assert_raise(JSON::ParserError) { parse('{false}') }
    assert_equal({ "a" => true }, parse('{"a":true}'))
    assert_equal({ "a" => true }, parse('  { "a" :  true  }   '))
    assert_equal({ "a" => -23 }, parse('  {  "a"  :  -23  }  '))
    assert_equal({ "a" => -23 }, parse('  { "a" : -23 } '))
    assert_equal({ "a" => 23 }, parse('{"a":23  } '))
    assert_equal({ "a" => 23 }, parse('  { "a"  : 23  } '))
    assert_equal({ "a" => 0.23 }, parse(' { "a"  :  0.23 }  '))
    assert_equal({ "a" => 0.23 }, parse('  {  "a"  :  0.23  }  '))
  end

  def test_parse_numbers
    assert_raise(JSON::ParserError) { parse('+23.2') }
    assert_raise(JSON::ParserError) { parse('+23') }
    assert_raise(JSON::ParserError) { parse('.23') }
    assert_raise(JSON::ParserError) { parse('023') }
    assert_equal(23, parse('23'))
    assert_equal(-23, parse('-23'))
    assert_equal_float(3.141, parse('3.141'))
    assert_equal_float(-3.141, parse('-3.141'))
    assert_equal_float(3.141, parse('3141e-3'))
    assert_equal_float(3.141, parse('3141.1e-3'))
    assert_equal_float(3.141, parse('3141E-3'))
    assert_equal_float(3.141, parse('3141.0E-3'))
    assert_equal_float(-3.141, parse('-3141.0e-3'))
    assert_equal_float(-3.141, parse('-3141e-3'))
    assert_raise(ParserError) { parse('NaN') }
    assert parse('NaN', :allow_nan => true).nan?
    assert_raise(ParserError) { parse('Infinity') }
    assert_equal(1.0/0, parse('Infinity', :allow_nan => true))
    assert_raise(ParserError) { parse('-Infinity') }
    assert_equal(-1.0/0, parse('-Infinity', :allow_nan => true))
  end

  def test_parse_bigdecimals
    assert_equal(BigDecimal,                             JSON.parse('{"foo": 9.01234567890123456789}', decimal_class: BigDecimal)["foo"].class)
    assert_equal(BigDecimal("0.901234567890123456789E1"),JSON.parse('{"foo": 9.01234567890123456789}', decimal_class: BigDecimal)["foo"]      )
  end

  if Array.method_defined?(:permutation)
    def test_parse_more_complex_arrays
      a = [ nil, false, true, "foßbar", [ "n€st€d", true ], { "nested" => true, "n€ßt€ð2" => {} }]
      a.permutation.each do |perm|
        json = pretty_generate(perm)
        assert_equal perm, parse(json)
      end
    end

    def test_parse_complex_objects
      a = [ nil, false, true, "foßbar", [ "n€st€d", true ], { "nested" => true, "n€ßt€ð2" => {} }]
      a.permutation.each do |perm|
        s = "a"
        orig_obj = perm.inject({}) { |h, x| h[s.dup] = x; s = s.succ; h }
        json = pretty_generate(orig_obj)
        assert_equal orig_obj, parse(json)
      end
    end
  end

  def test_parse_arrays
    assert_equal([1,2,3], parse('[1,2,3]'))
    assert_equal([1.2,2,3], parse('[1.2,2,3]'))
    assert_equal([[],[[],[]]], parse('[[],[[],[]]]'))
    assert_equal([], parse('[]'))
    assert_equal([], parse('  [  ]  '))
    assert_equal([1], parse('[1]'))
    assert_equal([1], parse('  [ 1  ]  '))
    ary = [[1], ["foo"], [3.14], [4711.0], [2.718], [nil],
      [[1, -2, 3]], [false], [true]]
    assert_equal(ary,
      parse('[[1],["foo"],[3.14],[47.11e+2],[2718.0E-3],[null],[[1,-2,3]],[false],[true]]'))
    assert_equal(ary, parse(%Q{   [   [1] , ["foo"]  ,  [3.14] \t ,  [47.11e+2]\s
      , [2718.0E-3 ],\r[ null] , [[1, -2, 3 ]], [false ],[ true]\n ]  }))
  end

  def test_parse_json_primitive_values
    assert_raise(JSON::ParserError) { parse('') }
    assert_raise(TypeError) { parse(nil) }
    assert_raise(JSON::ParserError) { parse('  /* foo */ ') }
    assert_equal nil, parse('null')
    assert_equal false, parse('false')
    assert_equal true, parse('true')
    assert_equal 23, parse('23')
    assert_equal 1, parse('1')
    assert_equal_float 3.141, parse('3.141'), 1E-3
    assert_equal 2 ** 64, parse('18446744073709551616')
    assert_equal 'foo', parse('"foo"')
    assert parse('NaN', :allow_nan => true).nan?
    assert parse('Infinity', :allow_nan => true).infinite?
    assert parse('-Infinity', :allow_nan => true).infinite?
    assert_raise(JSON::ParserError) { parse('[ 1, ]') }
  end

  def test_parse_some_strings
    assert_equal([""], parse('[""]'))
    assert_equal(["\\"], parse('["\\\\"]'))
    assert_equal(['"'], parse('["\""]'))
    assert_equal(['\\"\\'], parse('["\\\\\\"\\\\"]'))
    assert_equal(
      ["\"\b\n\r\t\0\037"],
      parse('["\"\b\n\r\t\u0000\u001f"]')
    )
  end

  def test_parse_big_integers
    json1 = JSON(orig = (1 << 31) - 1)
    assert_equal orig, parse(json1)
    json2 = JSON(orig = 1 << 31)
    assert_equal orig, parse(json2)
    json3 = JSON(orig = (1 << 62) - 1)
    assert_equal orig, parse(json3)
    json4 = JSON(orig = 1 << 62)
    assert_equal orig, parse(json4)
    json5 = JSON(orig = 1 << 64)
    assert_equal orig, parse(json5)
  end

  def test_some_wrong_inputs
    assert_raise(ParserError) { parse('[] bla') }
    assert_raise(ParserError) { parse('[] 1') }
    assert_raise(ParserError) { parse('[] []') }
    assert_raise(ParserError) { parse('[] {}') }
    assert_raise(ParserError) { parse('{} []') }
    assert_raise(ParserError) { parse('{} {}') }
    assert_raise(ParserError) { parse('[NULL]') }
    assert_raise(ParserError) { parse('[FALSE]') }
    assert_raise(ParserError) { parse('[TRUE]') }
    assert_raise(ParserError) { parse('[07]    ') }
    assert_raise(ParserError) { parse('[0a]') }
    assert_raise(ParserError) { parse('[1.]') }
    assert_raise(ParserError) { parse('     ') }
  end

  def test_symbolize_names
    assert_equal({ "foo" => "bar", "baz" => "quux" },
      parse('{"foo":"bar", "baz":"quux"}'))
    assert_equal({ :foo => "bar", :baz => "quux" },
      parse('{"foo":"bar", "baz":"quux"}', :symbolize_names => true))
    assert_raise(ArgumentError) do
      parse('{}', :symbolize_names => true, :create_additions => true)
    end
  end

  def test_parse_comments
    json = <<EOT
{
  "key1":"value1", // eol comment
  "key2":"value2"  /* multi line
                    *  comment */,
  "key3":"value3"  /* multi line
                    // nested eol comment
                    *  comment */
}
EOT
    assert_equal(
      { "key1" => "value1", "key2" => "value2", "key3" => "value3" },
      parse(json))
    json = <<EOT
{
  "key1":"value1"  /* multi line
                    // nested eol comment
                    /* illegal nested multi line comment */
                    *  comment */
}
EOT
    assert_raise(ParserError) { parse(json) }
    json = <<EOT
{
  "key1":"value1"  /* multi line
                   // nested eol comment
                   closed multi comment */
                   and again, throw an Error */
}
EOT
    assert_raise(ParserError) { parse(json) }
    json = <<EOT
{
  "key1":"value1"  /*/*/
}
EOT
    assert_equal({ "key1" => "value1" }, parse(json))
  end

  def test_nesting
    too_deep = '[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[["Too deep"]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]'
    too_deep_ary = eval too_deep
    assert_raise(JSON::NestingError) { parse too_deep }
    assert_raise(JSON::NestingError) { parse too_deep, :max_nesting => 100 }
    ok = parse too_deep, :max_nesting => 101
    assert_equal too_deep_ary, ok
    ok = parse too_deep, :max_nesting => nil
    assert_equal too_deep_ary, ok
    ok = parse too_deep, :max_nesting => false
    assert_equal too_deep_ary, ok
    ok = parse too_deep, :max_nesting => 0
    assert_equal too_deep_ary, ok
  end

  def test_backslash
    data = [ '\\.(?i:gif|jpe?g|png)$' ]
    json = '["\\\\.(?i:gif|jpe?g|png)$"]'
    assert_equal data, parse(json)
    #
    data = [ '\\"' ]
    json = '["\\\\\""]'
    assert_equal data, parse(json)
    #
    json = '["/"]'
    data = [ '/' ]
    assert_equal data, parse(json)
    #
    json = '["\""]'
    data = ['"']
    assert_equal data, parse(json)
    #
    json = '["\\\'"]'
    data = ["'"]
    assert_equal data, parse(json)

    json = '["\/"]'
    data = [ '/' ]
    assert_equal data, parse(json)
  end

  class SubArray < Array
    def <<(v)
      @shifted = true
      super
    end

    def shifted?
      @shifted
    end
  end

  class SubArray2 < Array
    def to_json(*a)
      {
        JSON.create_id => self.class.name,
        'ary'          => to_a,
      }.to_json(*a)
    end

    def self.json_create(o)
      o.delete JSON.create_id
      o['ary']
    end
  end

  class SubArrayWrapper
    def initialize
      @data = []
    end

    attr_reader :data

    def [](index)
      @data[index]
    end

    def <<(value)
      @data << value
      @shifted = true
    end

    def shifted?
      @shifted
    end
  end

  def test_parse_array_custom_array_derived_class
    res = parse('[1,2]', :array_class => SubArray)
    assert_equal([1,2], res)
    assert_equal(SubArray, res.class)
    assert res.shifted?
  end

  def test_parse_array_custom_non_array_derived_class
    res = parse('[1,2]', :array_class => SubArrayWrapper)
    assert_equal([1,2], res.data)
    assert_equal(SubArrayWrapper, res.class)
    assert res.shifted?
  end

  def test_parse_object
    assert_equal({}, parse('{}'))
    assert_equal({}, parse('  {  }  '))
    assert_equal({'foo'=>'bar'}, parse('{"foo":"bar"}'))
    assert_equal({'foo'=>'bar'}, parse('    { "foo"  :   "bar"   }   '))
  end

  class SubHash < Hash
    def []=(k, v)
      @item_set = true
      super
    end

    def item_set?
      @item_set
    end
  end

  class SubHash2 < Hash
    def to_json(*a)
      {
        JSON.create_id => self.class.name,
      }.merge(self).to_json(*a)
    end

    def self.json_create(o)
      o.delete JSON.create_id
      self[o]
    end
  end

  class SubOpenStruct < OpenStruct
    def [](k)
      __send__(k)
    end

    def []=(k, v)
      @item_set = true
      __send__("#{k}=", v)
    end

    def item_set?
      @item_set
    end
  end

  def test_parse_object_custom_hash_derived_class
    res = parse('{"foo":"bar"}', :object_class => SubHash)
    assert_equal({"foo" => "bar"}, res)
    assert_equal(SubHash, res.class)
    assert res.item_set?
  end

  def test_parse_object_custom_non_hash_derived_class
    res = parse('{"foo":"bar"}', :object_class => SubOpenStruct)
    assert_equal "bar", res.foo
    assert_equal(SubOpenStruct, res.class)
    assert res.item_set?
  end

  def test_parse_generic_object
    res = parse(
      '{"foo":"bar", "baz":{}}',
      :object_class => JSON::GenericObject
    )
    assert_equal(JSON::GenericObject, res.class)
    assert_equal "bar", res.foo
    assert_equal "bar", res["foo"]
    assert_equal "bar", res[:foo]
    assert_equal "bar", res.to_hash[:foo]
    assert_equal(JSON::GenericObject, res.baz.class)
  end

  def test_generate_core_subclasses_with_new_to_json
    obj = SubHash2["foo" => SubHash2["bar" => true]]
    obj_json = JSON(obj)
    obj_again = parse(obj_json, :create_additions => true)
    assert_kind_of SubHash2, obj_again
    assert_kind_of SubHash2, obj_again['foo']
    assert obj_again['foo']['bar']
    assert_equal obj, obj_again
    assert_equal ["foo"],
      JSON(JSON(SubArray2["foo"]), :create_additions => true)
  end

  def test_generate_core_subclasses_with_default_to_json
    assert_equal '{"foo":"bar"}', JSON(SubHash["foo" => "bar"])
    assert_equal '["foo"]', JSON(SubArray["foo"])
  end

  def test_generate_of_core_subclasses
    obj = SubHash["foo" => SubHash["bar" => true]]
    obj_json = JSON(obj)
    obj_again = JSON(obj_json)
    assert_kind_of Hash, obj_again
    assert_kind_of Hash, obj_again['foo']
    assert obj_again['foo']['bar']
    assert_equal obj, obj_again
  end

  def test_parsing_frozen_ascii8bit_string
    assert_equal(
      { 'foo' => 'bar' },
      JSON('{ "foo": "bar" }'.force_encoding(Encoding::ASCII_8BIT).freeze)
    )
  end

  private

  def assert_equal_float(expected, actual, delta = 1e-2)
    Array === expected and expected = expected.first
    Array === actual and actual = actual.first
    assert_in_delta(expected, actual, delta)
  end
end
