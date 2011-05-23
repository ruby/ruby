#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'test/unit'
case ENV['JSON']
when 'pure' then require 'json/pure'
when 'ext'  then require 'json/ext'
else             require 'json'
end
require 'stringio'

unless Array.method_defined?(:permutation)
  begin
    require 'enumerator'
    require 'permutation'
    class Array
      def permutation
        Permutation.for(self).to_enum.map { |x| x.project }
      end
    end
  rescue LoadError
    warn "Skipping permutation tests."
  end
end

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
    @json = '{"a":2,"b":3.141,"c":"c","d":[1,"b",3.14],"e":{"foo":"bar"},'\
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
    assert_raises(JSON::ParserError) { parse('[+23.2]') }
    assert_raises(JSON::ParserError) { parse('[+23]') }
    assert_raises(JSON::ParserError) { parse('[.23]') }
    assert_raises(JSON::ParserError) { parse('[023]') }
    assert_equal_float [3.141], parse('[3.141]')
    assert_equal_float [-3.141], parse('[-3.141]')
    assert_equal_float [3.141], parse('[3141e-3]')
    assert_equal_float [3.141], parse('[3141.1e-3]')
    assert_equal_float [3.141], parse('[3141E-3]')
    assert_equal_float [3.141], parse('[3141.0E-3]')
    assert_equal_float [-3.141], parse('[-3141.0e-3]')
    assert_equal_float [-3.141], parse('[-3141e-3]')
    assert_raises(ParserError) { parse('[NaN]') }
    assert parse('[NaN]', :allow_nan => true).first.nan?
    assert_raises(ParserError) { parse('[Infinity]') }
    assert_equal [1.0/0], parse('[Infinity]', :allow_nan => true)
    assert_raises(ParserError) { parse('[-Infinity]') }
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
    assert_raises(JSON::ParserError) { parse('{false}') }
    assert_equal({ "a" => true }, parse('{"a":true}'))
    assert_equal({ "a" => true }, parse('  { "a" :  true  }   '))
    assert_equal({ "a" => -23 }, parse('  {  "a"  :  -23  }  '))
    assert_equal({ "a" => -23 }, parse('  { "a" : -23 } '))
    assert_equal({ "a" => 23 }, parse('{"a":23  } '))
    assert_equal({ "a" => 23 }, parse('  { "a"  : 23  } '))
    assert_equal({ "a" => 0.23 }, parse(' { "a"  :  0.23 }  '))
    assert_equal({ "a" => 0.23 }, parse('  {  "a"  :  0.23  }  '))
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

  class SubArray < Array; end

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

  def test_parse_array_custom_class
    res = parse('[]', :array_class => SubArray)
    assert_equal([], res)
    assert_equal(SubArray, res.class)
  end

  def test_parse_object
    assert_equal({}, parse('{}'))
    assert_equal({}, parse('  {  }  '))
    assert_equal({'foo'=>'bar'}, parse('{"foo":"bar"}'))
    assert_equal({'foo'=>'bar'}, parse('    { "foo"  :   "bar"   }   '))
  end

  class SubHash < Hash
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

  def test_parse_object_custom_class
    res = parse('{}', :object_class => SubHash2)
    assert_equal({}, res)
    assert_equal(SubHash2, res.class)
  end

  def test_generation_of_core_subclasses_with_new_to_json
    obj = SubHash2["foo" => SubHash2["bar" => true]]
    obj_json = JSON(obj)
    obj_again = JSON(obj_json)
    assert_kind_of SubHash2, obj_again
    assert_kind_of SubHash2, obj_again['foo']
    assert obj_again['foo']['bar']
    assert_equal obj, obj_again
    assert_equal ["foo"], JSON(JSON(SubArray2["foo"]))
  end

  def test_generation_of_core_subclasses_with_default_to_json
    assert_equal '{"foo":"bar"}', JSON(SubHash["foo" => "bar"])
    assert_equal '["foo"]', JSON(SubArray["foo"])
  end

  def test_generation_of_core_subclasses
    obj = SubHash["foo" => SubHash["bar" => true]]
    obj_json = JSON(obj)
    obj_again = JSON(obj_json)
    assert_kind_of Hash, obj_again
    assert_kind_of Hash, obj_again['foo']
    assert obj_again['foo']['bar']
    assert_equal obj, obj_again
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
    assert_raises(ParserError) { parse(json) }
    json = <<EOT
{
  "key1":"value1"  /* multi line
                   // nested eol comment
                   closed multi comment */
                   and again, throw an Error */
}
EOT
    assert_raises(ParserError) { parse(json) }
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
    assert_equal json, JSON.generate(data)
    assert_equal data, JSON.parse(json)
    #
    data = [ '\\"' ]
    json = '["\\\\\""]'
    assert_equal json, JSON.generate(data)
    assert_equal data, JSON.parse(json)
    #
    json = '["/"]'
    data = JSON.parse(json)
    assert_equal ['/'], data
    assert_equal json, JSON.generate(data)
    #
    json = '["\""]'
    data = JSON.parse(json)
    assert_equal ['"'], data
    assert_equal json, JSON.generate(data)
    json = '["\\\'"]'
    data = JSON.parse(json)
    assert_equal ["'"], data
    assert_equal '["\'"]', JSON.generate(data)
  end

  def test_wrong_inputs
    assert_raises(ParserError) { JSON.parse('"foo"') }
    assert_raises(ParserError) { JSON.parse('123') }
    assert_raises(ParserError) { JSON.parse('[] bla') }
    assert_raises(ParserError) { JSON.parse('[] 1') }
    assert_raises(ParserError) { JSON.parse('[] []') }
    assert_raises(ParserError) { JSON.parse('[] {}') }
    assert_raises(ParserError) { JSON.parse('{} []') }
    assert_raises(ParserError) { JSON.parse('{} {}') }
    assert_raises(ParserError) { JSON.parse('[NULL]') }
    assert_raises(ParserError) { JSON.parse('[FALSE]') }
    assert_raises(ParserError) { JSON.parse('[TRUE]') }
    assert_raises(ParserError) { JSON.parse('[07]    ') }
    assert_raises(ParserError) { JSON.parse('[0a]') }
    assert_raises(ParserError) { JSON.parse('[1.]') }
    assert_raises(ParserError) { JSON.parse('     ') }
  end

  def test_nesting
    assert_raises(JSON::NestingError) { JSON.parse '[[]]', :max_nesting => 1 }
    assert_raises(JSON::NestingError) { JSON.parser.new('[[]]', :max_nesting => 1).parse }
    assert_equal [[]], JSON.parse('[[]]', :max_nesting => 2)
    too_deep = '[[[[[[[[[[[[[[[[[[[["Too deep"]]]]]]]]]]]]]]]]]]]]'
    too_deep_ary = eval too_deep
    assert_raises(JSON::NestingError) { JSON.parse too_deep }
    assert_raises(JSON::NestingError) { JSON.parser.new(too_deep).parse }
    assert_raises(JSON::NestingError) { JSON.parse too_deep, :max_nesting => 19 }
    ok = JSON.parse too_deep, :max_nesting => 20
    assert_equal too_deep_ary, ok
    ok = JSON.parse too_deep, :max_nesting => nil
    assert_equal too_deep_ary, ok
    ok = JSON.parse too_deep, :max_nesting => false
    assert_equal too_deep_ary, ok
    ok = JSON.parse too_deep, :max_nesting => 0
    assert_equal too_deep_ary, ok
    assert_raises(JSON::NestingError) { JSON.generate [[]], :max_nesting => 1 }
    assert_equal '[[]]', JSON.generate([[]], :max_nesting => 2)
    assert_raises(JSON::NestingError) { JSON.generate too_deep_ary }
    assert_raises(JSON::NestingError) { JSON.generate too_deep_ary, :max_nesting => 19 }
    ok = JSON.generate too_deep_ary, :max_nesting => 20
    assert_equal too_deep, ok
    ok = JSON.generate too_deep_ary, :max_nesting => nil
    assert_equal too_deep, ok
    ok = JSON.generate too_deep_ary, :max_nesting => false
    assert_equal too_deep, ok
    ok = JSON.generate too_deep_ary, :max_nesting => 0
    assert_equal too_deep, ok
  end

  def test_symbolize_names
    assert_equal({ "foo" => "bar", "baz" => "quux" },
      JSON.parse('{"foo":"bar", "baz":"quux"}'))
    assert_equal({ :foo => "bar", :baz => "quux" },
      JSON.parse('{"foo":"bar", "baz":"quux"}', :symbolize_names => true))
  end

  def test_load_dump
    too_deep = '[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]'
    assert_equal too_deep, JSON.dump(eval(too_deep))
    assert_kind_of String, Marshal.dump(eval(too_deep))
    assert_raises(ArgumentError) { JSON.dump(eval(too_deep), 19) }
    assert_raises(ArgumentError) { Marshal.dump(eval(too_deep), 19) }
    assert_equal too_deep, JSON.dump(eval(too_deep), 20)
    assert_kind_of String, Marshal.dump(eval(too_deep), 20)
    output = StringIO.new
    JSON.dump(eval(too_deep), output)
    assert_equal too_deep, output.string
    output = StringIO.new
    JSON.dump(eval(too_deep), output, 20)
    assert_equal too_deep, output.string
  end

  def test_big_integers
    json1 = JSON([orig = (1 << 31) - 1])
    assert_equal orig, JSON[json1][0]
    json2 = JSON([orig = 1 << 31])
    assert_equal orig, JSON[json2][0]
    json3 = JSON([orig = (1 << 62) - 1])
    assert_equal orig, JSON[json3][0]
    json4 = JSON([orig = 1 << 62])
    assert_equal orig, JSON[json4][0]
    json5 = JSON([orig = 1 << 64])
    assert_equal orig, JSON[json5][0]
  end

  def test_allocate
    json = JSON::Parser.new("{}")
    assert_raises(TypeError, '[ruby-core:35079]') {json.__send__(:initialize, "{}")}
    json = JSON::Parser.allocate
    assert_raises(TypeError, '[ruby-core:35079]') {json.source}
  end
end
