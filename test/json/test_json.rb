#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'test/unit'
require 'json'
require 'stringio'

class TC_JSON < Test::Unit::TestCase
  include JSON

  def setup
    @ary = [1, "foo", 3.14, 4711.0, 2.718, nil, [1,-2,3], false, true].map do
      |x| [x]
    end
    @ary_to_parse = ["1", '"foo"', "3.14", "4711.0", "2.718", "null",
      "[1,-2,3]", "false", "true"].map do
      |x| "[#{x}]"
    end
    @hash = {
      'a' => 2,
      'b' => 3.141,
      'c' => 'c',
      'd' => [ 1, "b", 3.14 ],
      'e' => { 'foo' => 'bar' },
      'g' => "\"\0\037",
      'h' => 1000.0,
      'i' => 0.001
    }
    @json = '{"a":2,"b":3.141,"c":"c","d":[1,"b",3.14],"e":{"foo":"bar"},' +
      '"g":"\\"\\u0000\\u001f","h":1.0E3,"i":1.0E-3}'
  end

  def test_construction
    parser = JSON::Parser.new('test')
    assert_equal 'test', parser.source
  end

  def assert_equal_float(expected, is)
    assert_in_delta(expected.first, is.first, 1e-2)
  end

  def test_parse_simple_arrays
    assert_equal([], parse('[]'))
    assert_equal([], parse('  [  ] '))
    assert_equal([nil], parse('[null]'))
    assert_equal([false], parse('[false]'))
    assert_equal([true], parse('[true]'))
    assert_equal([-23], parse('[-23]'))
    assert_equal([23], parse('[23]'))
    assert_equal([0.23], parse('[0.23]'))
    assert_equal([0.0], parse('[0e0]'))
    assert_raise(JSON::ParserError) { parse('[+23.2]') }
    assert_raise(JSON::ParserError) { parse('[+23]') }
    assert_raise(JSON::ParserError) { parse('[.23]') }
    assert_raise(JSON::ParserError) { parse('[023]') }
    assert_equal_float [3.141], parse('[3.141]')
    assert_equal_float [-3.141], parse('[-3.141]')
    assert_equal_float [3.141], parse('[3141e-3]')
    assert_equal_float [3.141], parse('[3141.1e-3]')
    assert_equal_float [3.141], parse('[3141E-3]')
    assert_equal_float [3.141], parse('[3141.0E-3]')
    assert_equal_float [-3.141], parse('[-3141.0e-3]')
    assert_equal_float [-3.141], parse('[-3141e-3]')
    assert_raise(ParserError) { parse('[NaN]') }
    assert parse('[NaN]', :allow_nan => true).first.nan?
    assert_raise(ParserError) { parse('[Infinity]') }
    assert_equal [1.0/0], parse('[Infinity]', :allow_nan => true)
    assert_raise(ParserError) { parse('[-Infinity]') }
    assert_equal [-1.0/0], parse('[-Infinity]', :allow_nan => true)
    assert_equal([""], parse('[""]'))
    assert_equal(["foobar"], parse('["foobar"]'))
    assert_equal([{}], parse('[{}]'))
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

  def test_parse_more_complex_arrays
    a = [ nil, false, true, "foßbar", [ "n€st€d", true ], { "nested" => true, "n€ßt€ð2" => {} }]
    a.permutation do |orig_ary|
      json = pretty_generate(orig_ary)
      assert_equal orig_ary, parse(json)
    end
  end

  def test_parse_complex_objects
    a = [ nil, false, true, "foßbar", [ "n€st€d", true ], { "nested" => true, "n€ßt€ð2" => {} }]
    a.permutation do |orig_ary|
      s = "a"
      orig_obj = orig_ary.inject({}) { |h, x| h[s.dup] = x; s = s.succ; h }
      json = pretty_generate(orig_obj)
      assert_equal orig_obj, parse(json)
    end
  end

  def test_parse_arrays
    assert_equal([1,2,3], parse('[1,2,3]'))
    assert_equal([1.2,2,3], parse('[1.2,2,3]'))
    assert_equal([[],[[],[]]], parse('[[],[[],[]]]'))
  end

  def test_parse_values
    assert_equal([""], parse('[""]'))
    assert_equal(["\\"], parse('["\\\\"]'))
    assert_equal(['"'], parse('["\""]'))
    assert_equal(['\\"\\'], parse('["\\\\\\"\\\\"]'))
    assert_equal(["\"\b\n\r\t\0\037"],
      parse('["\"\b\n\r\t\u0000\u001f"]'))
    for i in 0 ... @ary.size
      assert_equal(@ary[i], parse(@ary_to_parse[i]))
    end
  end

  def test_parse_array
    assert_equal([], parse('[]'))
    assert_equal([], parse('  [  ]  '))
    assert_equal([1], parse('[1]'))
    assert_equal([1], parse('  [ 1  ]  '))
    assert_equal(@ary,
      parse('[[1],["foo"],[3.14],[47.11e+2],[2718.0E-3],[null],[[1,-2,3]]'\
      ',[false],[true]]'))
    assert_equal(@ary, parse(%Q{   [   [1] , ["foo"]  ,  [3.14] \t ,  [47.11e+2]
      , [2718.0E-3 ],\r[ null] , [[1, -2, 3 ]], [false ],[ true]\n ]  }))
  end

  def test_parse_object
    assert_equal({}, parse('{}'))
    assert_equal({}, parse('  {  }  '))
    assert_equal({'foo'=>'bar'}, parse('{"foo":"bar"}'))
    assert_equal({'foo'=>'bar'}, parse('    { "foo"  :   "bar"   }   '))
  end

  def test_parser_reset
    parser = Parser.new(@json)
    assert_equal(@hash, parser.parse)
    assert_equal(@hash, parser.parse)
  end

  def test_comments
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

  def test_backslash
    data = [ '\\.(?i:gif|jpe?g|png)$' ]
    json = '["\\\\.(?i:gif|jpe?g|png)$"]'
    assert_equal json, JSON.unparse(data)
    assert_equal data, JSON.parse(json)
    #
    data = [ '\\"' ]
    json = '["\\\\\""]'
    assert_equal json, JSON.unparse(data)
    assert_equal data, JSON.parse(json)
    #
    json = '["\/"]'
    data = JSON.parse(json)
    assert_equal ['/'], data
    assert_equal json, JSON.unparse(data)
    #
    json = '["\""]'
    data = JSON.parse(json)
    assert_equal ['"'], data
    assert_equal json, JSON.unparse(data)
    json = '["\\\'"]'
    data = JSON.parse(json)
    assert_equal ["'"], data
    assert_equal '["\'"]', JSON.unparse(data)
  end

  def test_wrong_inputs
    assert_raise(ParserError) { JSON.parse('"foo"') }
    assert_raise(ParserError) { JSON.parse('123') }
    assert_raise(ParserError) { JSON.parse('[] bla') }
    assert_raise(ParserError) { JSON.parse('[] 1') }
    assert_raise(ParserError) { JSON.parse('[] []') }
    assert_raise(ParserError) { JSON.parse('[] {}') }
    assert_raise(ParserError) { JSON.parse('{} []') }
    assert_raise(ParserError) { JSON.parse('{} {}') }
    assert_raise(ParserError) { JSON.parse('[NULL]') }
    assert_raise(ParserError) { JSON.parse('[FALSE]') }
    assert_raise(ParserError) { JSON.parse('[TRUE]') }
    assert_raise(ParserError) { JSON.parse('[07]    ') }
    assert_raise(ParserError) { JSON.parse('[0a]') }
    assert_raise(ParserError) { JSON.parse('[1.]') }
    assert_raise(ParserError) { JSON.parse('     ') }
  end

  def test_nesting
    assert_raise(JSON::NestingError) { JSON.parse '[[]]', :max_nesting => 1 }
    assert_raise(JSON::NestingError) { JSON.parser.new('[[]]', :max_nesting => 1).parse }
    assert_equal [[]], JSON.parse('[[]]', :max_nesting => 2)
    too_deep = '[[[[[[[[[[[[[[[[[[[["Too deep"]]]]]]]]]]]]]]]]]]]]'
    too_deep_ary = eval too_deep
    assert_raise(JSON::NestingError) { JSON.parse too_deep }
    assert_raise(JSON::NestingError) { JSON.parser.new(too_deep).parse }
    assert_raise(JSON::NestingError) { JSON.parse too_deep, :max_nesting => 19 }
    ok = JSON.parse too_deep, :max_nesting => 20
    assert_equal too_deep_ary, ok
    ok = JSON.parse too_deep, :max_nesting => nil
    assert_equal too_deep_ary, ok
    ok = JSON.parse too_deep, :max_nesting => false
    assert_equal too_deep_ary, ok
    ok = JSON.parse too_deep, :max_nesting => 0
    assert_equal too_deep_ary, ok
    assert_raise(JSON::NestingError) { JSON.generate [[]], :max_nesting => 1 }
    assert_equal '[[]]', JSON.generate([[]], :max_nesting => 2)
    assert_raise(JSON::NestingError) { JSON.generate too_deep_ary }
    assert_raise(JSON::NestingError) { JSON.generate too_deep_ary, :max_nesting => 19 }
    ok = JSON.generate too_deep_ary, :max_nesting => 20
    assert_equal too_deep, ok
    ok = JSON.generate too_deep_ary, :max_nesting => nil
    assert_equal too_deep, ok
    ok = JSON.generate too_deep_ary, :max_nesting => false
    assert_equal too_deep, ok
    ok = JSON.generate too_deep_ary, :max_nesting => 0
    assert_equal too_deep, ok
  end

  def test_load_dump
    too_deep = '[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]'
    assert_equal too_deep, JSON.dump(eval(too_deep))
    assert_kind_of String, Marshal.dump(eval(too_deep))
    assert_raise(ArgumentError) { JSON.dump(eval(too_deep), 19) }
    assert_raise(ArgumentError) { Marshal.dump(eval(too_deep), 19) }
    assert_equal too_deep, JSON.dump(eval(too_deep), 20)
    assert_kind_of String, Marshal.dump(eval(too_deep), 20)
    output = StringIO.new
    JSON.dump(eval(too_deep), output)
    assert_equal too_deep, output.string
    output = StringIO.new
    JSON.dump(eval(too_deep), output, 20)
    assert_equal too_deep, output.string
  end
end
