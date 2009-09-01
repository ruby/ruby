#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'test/unit'
case ENV['JSON']
when 'pure' then require 'json/pure'
when 'ext'  then require 'json/ext'
else             require 'json'
end

class TC_JSONGenerate < Test::Unit::TestCase
  include JSON

  def setup
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
    @json2 = '{"a":2,"b":3.141,"c":"c","d":[1,"b",3.14],"e":{"foo":"bar"},' +
      '"g":"\\"\\u0000\\u001f","h":1000.0,"i":0.001}'
    @json3 = <<'EOT'.chomp
{
  "a": 2,
  "b": 3.141,
  "c": "c",
  "d": [
    1,
    "b",
    3.14
  ],
  "e": {
    "foo": "bar"
  },
  "g": "\"\u0000\u001f",
  "h": 1000.0,
  "i": 0.001
}
EOT
  end

  def test_unparse
    json = unparse(@hash)
    assert_equal(JSON.parse(@json2), JSON.parse(json))
    parsed_json = parse(json)
    assert_equal(@hash, parsed_json)
    json = generate({1=>2})
    assert_equal('{"1":2}', json)
    parsed_json = parse(json)
    assert_equal({"1"=>2}, parsed_json)
  end

  def test_unparse_pretty
    json = pretty_unparse(@hash)
    assert_equal(JSON.parse(@json3), JSON.parse(json))
    parsed_json = parse(json)
    assert_equal(@hash, parsed_json)
    json = pretty_generate({1=>2})
    assert_equal(<<'EOT'.chomp, json)
{
  "1": 2
}
EOT
    parsed_json = parse(json)
    assert_equal({"1"=>2}, parsed_json)
  end

  def test_states
    json = generate({1=>2}, nil)
    assert_equal('{"1":2}', json)
    s = JSON.state.new(:check_circular => true)
    #assert s.check_circular
    h = { 1=>2 }
    h[3] = h
    assert_raises(JSON::CircularDatastructure) {  generate(h) }
    assert_raises(JSON::CircularDatastructure) {  generate(h, s) }
    s = JSON.state.new(:check_circular => true)
    #assert s.check_circular
    a = [ 1, 2 ]
    a << a
    assert_raises(JSON::CircularDatastructure) {  generate(a, s) }
  end

  def test_allow_nan
    assert_raises(GeneratorError) { generate([JSON::NaN]) }
    assert_equal '[NaN]', generate([JSON::NaN], :allow_nan => true)
    assert_equal '[NaN]', fast_generate([JSON::NaN])
    assert_raises(GeneratorError) { pretty_generate([JSON::NaN]) }
    assert_equal "[\n  NaN\n]", pretty_generate([JSON::NaN], :allow_nan => true)
    assert_raises(GeneratorError) { generate([JSON::Infinity]) }
    assert_equal '[Infinity]', generate([JSON::Infinity], :allow_nan => true)
    assert_equal '[Infinity]', fast_generate([JSON::Infinity])
    assert_raises(GeneratorError) { pretty_generate([JSON::Infinity]) }
    assert_equal "[\n  Infinity\n]", pretty_generate([JSON::Infinity], :allow_nan => true)
    assert_raises(GeneratorError) { generate([JSON::MinusInfinity]) }
    assert_equal '[-Infinity]', generate([JSON::MinusInfinity], :allow_nan => true)
    assert_equal '[-Infinity]', fast_generate([JSON::MinusInfinity])
    assert_raises(GeneratorError) { pretty_generate([JSON::MinusInfinity]) }
    assert_equal "[\n  -Infinity\n]", pretty_generate([JSON::MinusInfinity], :allow_nan => true)
  end
end
