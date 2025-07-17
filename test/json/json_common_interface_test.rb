# frozen_string_literal: true

require_relative 'test_helper'
require 'stringio'
require 'tempfile'

class JSONCommonInterfaceTest < Test::Unit::TestCase
  include JSON

  module MethodMissing
    def method_missing(name, *args); end
    def respond_to_missing?(name, include_private)
      true
    end
  end

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

    @hash_with_method_missing = {
      'a' => 2,
      'b' => 3.141,
      'c' => 'c',
      'd' => [ 1, "b", 3.14 ],
      'e' => { 'foo' => 'bar' },
      'g' => "\"\0\037",
      'h' => 1000.0,
      'i' => 0.001
    }
    @hash_with_method_missing.extend MethodMissing

    @json = '{"a":2,"b":3.141,"c":"c","d":[1,"b",3.14],"e":{"foo":"bar"},'\
      '"g":"\\"\\u0000\\u001f","h":1000.0,"i":0.001}'
  end

  def test_index
    assert_equal @json, JSON[@hash]
    assert_equal @json, JSON[@hash_with_method_missing]
    assert_equal @hash, JSON[@json]
  end

  def test_parser
    assert_match(/::Parser\z/, JSON.parser.name)
  end

  def test_generator
    assert_match(/::(TruffleRuby)?Generator\z/, JSON.generator.name)
  end

  def test_state
    assert_match(/::(TruffleRuby)?Generator::State\z/, JSON.state.name)
  end

  def test_create_id
    assert_equal 'json_class', JSON.create_id
    JSON.create_id = 'foo_bar'
    assert_equal 'foo_bar', JSON.create_id
  ensure
    JSON.create_id = 'json_class'
  end

  def test_deep_const_get
    assert_raise(ArgumentError) { JSON.deep_const_get('Nix::Da') }
    assert_equal File::SEPARATOR, JSON.deep_const_get('File::SEPARATOR')
  end

  def test_parse
    assert_equal [ 1, 2, 3, ], JSON.parse('[ 1, 2, 3 ]')
  end

  def test_parse_bang
    assert_equal [ 1, Infinity, 3, ], JSON.parse!('[ 1, Infinity, 3 ]')
  end

  def test_generate
    assert_equal '[1,2,3]', JSON.generate([ 1, 2, 3 ])
  end

  def test_fast_generate
    assert_equal '[1,2,3]', JSON.generate([ 1, 2, 3 ])
  end

  def test_pretty_generate
    assert_equal "[\n  1,\n  2,\n  3\n]", JSON.pretty_generate([ 1, 2, 3 ])
    assert_equal <<~JSON.strip, JSON.pretty_generate({ a: { b: "f"}, c: "d"})
      {
        "a": {
          "b": "f"
        },
        "c": "d"
      }
    JSON

    # Cause the state to be spilled on the heap.
    o = Object.new
    def o.to_s
      "Object"
    end
    actual = JSON.pretty_generate({ a: { b: o}, c: "d", e: "f"})
    assert_equal <<~JSON.strip, actual
      {
        "a": {
          "b": "Object"
        },
        "c": "d",
        "e": "f"
      }
    JSON
  end

  def test_load
    assert_equal @hash, JSON.load(@json)
    tempfile = Tempfile.open('@json')
    tempfile.write @json
    tempfile.rewind
    assert_equal @hash, JSON.load(tempfile)
    stringio = StringIO.new(@json)
    stringio.rewind
    assert_equal @hash, JSON.load(stringio)
    assert_equal nil, JSON.load(nil)
    assert_equal nil, JSON.load('')
  ensure
    tempfile.close!
  end

  def test_load_with_proc
    visited = []
    JSON.load('{"foo": [1, 2, 3], "bar": {"baz": "plop"}}', proc { |o| visited << JSON.dump(o); o })

    expected = [
      '"foo"',
      '1',
      '2',
      '3',
      '[1,2,3]',
      '"bar"',
      '"baz"',
      '"plop"',
      '{"baz":"plop"}',
      '{"foo":[1,2,3],"bar":{"baz":"plop"}}',
    ]
    assert_equal expected, visited
  end

  def test_load_with_options
    json  = '{ "foo": NaN }'
    assert JSON.load(json, nil, :allow_nan => true)['foo'].nan?
  end

  def test_load_null
    assert_equal nil, JSON.load(nil, nil, :allow_blank => true)
    assert_raise(TypeError) { JSON.load(nil, nil, :allow_blank => false) }
    assert_raise(JSON::ParserError) { JSON.load('', nil, :allow_blank => false) }
  end

  def test_dump
    too_deep = '[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]'
    obj = eval(too_deep)
    assert_equal too_deep, dump(obj)
    assert_kind_of String, Marshal.dump(obj)
    assert_raise(ArgumentError) { dump(obj, 100) }
    assert_raise(ArgumentError) { Marshal.dump(obj, 100) }
    assert_equal too_deep, dump(obj, 101)
    assert_kind_of String, Marshal.dump(obj, 101)

    assert_equal too_deep, JSON.dump(obj, StringIO.new, 101, strict: false).string
    assert_equal too_deep, dump(obj, StringIO.new, 101, strict: false).string
    assert_raise(JSON::GeneratorError) { JSON.dump(Object.new, StringIO.new, 101, strict: true).string }
    assert_raise(JSON::GeneratorError) { dump(Object.new, StringIO.new, 101, strict: true).string }

    assert_equal too_deep, dump(obj, nil, nil, strict: false)
    assert_equal too_deep, dump(obj, nil, 101, strict: false)
    assert_equal too_deep, dump(obj, StringIO.new, nil, strict: false).string
    assert_equal too_deep, dump(obj, nil, strict: false)
    assert_equal too_deep, dump(obj, 101, strict: false)
    assert_equal too_deep, dump(obj, StringIO.new, strict: false).string
    assert_equal too_deep, dump(obj, strict: false)
  end

  def test_dump_in_io
    io = StringIO.new
    assert_same io, JSON.dump([1], io)
    assert_equal "[1]", io.string

    big_object = ["a" * 10, "b" * 40, { foo: 1.23 }] * 5000
    io.rewind
    assert_same io, JSON.dump(big_object, io)
    assert_equal JSON.dump(big_object), io.string
  end

  def test_dump_should_modify_defaults
    max_nesting = JSON._dump_default_options[:max_nesting]
    dump([], StringIO.new, 10)
    assert_equal max_nesting, JSON._dump_default_options[:max_nesting]
  end

  def test_JSON
    assert_equal @json, JSON(@hash)
    assert_equal @json, JSON(@hash_with_method_missing)
    assert_equal @hash, JSON(@json)
  end

  def test_load_file
    test_load_shared(:load_file)
  end

  def test_load_file!
    test_load_shared(:load_file!)
  end

  def test_load_file_with_option
    test_load_file_with_option_shared(:load_file)
  end

  def test_load_file_with_option!
    test_load_file_with_option_shared(:load_file!)
  end

  def test_load_file_with_bad_default_external_encoding
    data = { "key" => "€" }
    temp_file_containing(JSON.dump(data)) do |path|
      loaded_data = with_external_encoding(Encoding::US_ASCII) do
        JSON.load_file(path)
      end
      assert_equal data, loaded_data
    end
  end

  def test_deprecated_dump_default_options
    assert_deprecated_warning(/dump_default_options/) do
      JSON.dump_default_options
    end
  end

  private

  def with_external_encoding(encoding)
    verbose = $VERBOSE
    $VERBOSE = nil
    previous_encoding = Encoding.default_external
    Encoding.default_external = encoding
    yield
  ensure
    Encoding.default_external = previous_encoding
    $VERBOSE = verbose
  end

  def test_load_shared(method_name)
    temp_file_containing(@json) do |filespec|
      assert_equal JSON.public_send(method_name, filespec), @hash
    end
  end

  def test_load_file_with_option_shared(method_name)
    temp_file_containing(@json) do |filespec|
      parsed_object = JSON.public_send(method_name, filespec, symbolize_names: true)
      key_classes = parsed_object.keys.map(&:class)
      assert_include(key_classes, Symbol)
      assert_not_include(key_classes, String)
    end
  end

  def temp_file_containing(text, file_prefix = '')
    raise "This method must be called with a code block." unless block_given?

    Tempfile.create(file_prefix) do |file|
      file << text
      file.close
      yield file.path
    end
  end
end
