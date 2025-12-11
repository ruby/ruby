#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'test_helper'

class JSONGeneratorTest < Test::Unit::TestCase
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
    @json3 = <<~'JSON'.chomp
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
    JSON
  end

  def silence
    v = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = v
  end

  def test_generate
    json = generate(@hash)
    assert_equal(parse(@json2), parse(json))
    json = JSON[@hash]
    assert_equal(parse(@json2), parse(json))
    parsed_json = parse(json)
    assert_equal(@hash, parsed_json)
    json = generate({1=>2})
    assert_equal('{"1":2}', json)
    parsed_json = parse(json)
    assert_equal({"1"=>2}, parsed_json)
    assert_equal '666', generate(666)
  end

  def test_dump_unenclosed_hash
    assert_equal '{"a":1,"b":2}', dump(a: 1, b: 2)
  end

  def test_dump_strict
    assert_equal '{}', dump({}, strict: true)

    assert_equal '{"array":[42,4.2,"forty-two",true,false,null]}', dump({
      "array" => [42, 4.2, "forty-two", true, false, nil]
    }, strict: true)

    assert_equal '{"int":42,"float":4.2,"string":"forty-two","true":true,"false":false,"nil":null,"hash":{}}', dump({
      "int" => 42,
      "float" => 4.2,
      "string" => "forty-two",
      "true" => true,
      "false" => false,
      "nil" => nil,
      "hash" => {},
    }, strict: true)

    assert_equal '[]', dump([], strict: true)

    assert_equal '42', dump(42, strict: true)
    assert_equal 'true', dump(true, strict: true)

    assert_equal '"hello"', dump(:hello, strict: true)
    assert_equal '"hello"', :hello.to_json(strict: true)
    assert_equal '"World"', "World".to_json(strict: true)
  end

  def test_state_depth_to_json
    depth = Object.new
    def depth.to_json(state)
      JSON::State.from_state(state).depth.to_s
    end

    assert_equal "0", JSON.generate(depth)
    assert_equal "[1]", JSON.generate([depth])
    assert_equal %({"depth":1}), JSON.generate(depth: depth)
    assert_equal "[[2]]", JSON.generate([[depth]])
    assert_equal %([{"depth":2}]), JSON.generate([{depth: depth}])

    state = JSON::State.new
    assert_equal "0", state.generate(depth)
    assert_equal "[1]", state.generate([depth])
    assert_equal %({"depth":1}), state.generate(depth: depth)
    assert_equal "[[2]]", state.generate([[depth]])
    assert_equal %([{"depth":2}]), state.generate([{depth: depth}])
  end

  def test_state_depth_to_json_recursive
    recur = Object.new
    def recur.to_json(state = nil, *)
      state = JSON::State.from_state(state)
      if state.depth < 3
        state.generate([state.depth, self])
      else
        state.generate([state.depth])
      end
    end

    assert_raise(NestingError) { JSON.generate(recur, max_nesting: 3) }
    assert_equal "[0,[1,[2,[3]]]]", JSON.generate(recur, max_nesting: 4)

    state = JSON::State.new(max_nesting: 3)
    assert_raise(NestingError) { state.generate(recur) }
    state.max_nesting = 4
    assert_equal "[0,[1,[2,[3]]]]", JSON.generate(recur, max_nesting: 4)
  end

  def test_generate_pretty
    json = pretty_generate({})
    assert_equal('{}', json)

    json = pretty_generate({1=>{}, 2=>[], 3=>4})
    assert_equal(<<~'JSON'.chomp, json)
      {
        "1": {},
        "2": [],
        "3": 4
      }
    JSON

    json = pretty_generate(@hash)
    # hashes aren't (insertion) ordered on every ruby implementation
    # assert_equal(@json3, json)
    assert_equal(parse(@json3), parse(json))
    parsed_json = parse(json)
    assert_equal(@hash, parsed_json)
    json = pretty_generate({1=>2})
    assert_equal(<<~'JSON'.chomp, json)
      {
        "1": 2
      }
    JSON
    parsed_json = parse(json)
    assert_equal({"1"=>2}, parsed_json)
    assert_equal '666', pretty_generate(666)
  end

  def test_generate_pretty_custom
    state = State.new(:space_before => "<psb>", :space => "<ps>", :indent => "<pi>", :object_nl => "\n<po_nl>\n", :array_nl => "<pa_nl>")
    json = pretty_generate({1=>{}, 2=>['a','b'], 3=>4}, state)
    assert_equal(<<~'JSON'.chomp, json)
      {
      <po_nl>
      <pi>"1"<psb>:<ps>{},
      <po_nl>
      <pi>"2"<psb>:<ps>[<pa_nl><pi><pi>"a",<pa_nl><pi><pi>"b"<pa_nl><pi>],
      <po_nl>
      <pi>"3"<psb>:<ps>4
      <po_nl>
      }
    JSON
  end

  def test_generate_custom
    state = State.new(:space_before => " ", :space => "   ", :indent => "<i>", :object_nl => "\n", :array_nl => "<a_nl>")
    json = generate({1=>{2=>3,4=>[5,6]}}, state)
    assert_equal(<<~'JSON'.chomp, json)
      {
      <i>"1" :   {
      <i><i>"2" :   3,
      <i><i>"4" :   [<a_nl><i><i><i>5,<a_nl><i><i><i>6<a_nl><i><i>]
      <i>}
      }
    JSON
  end

  def test_fast_generate
    assert_deprecated_warning(/fast_generate/) do
      json = fast_generate(@hash)
      assert_equal(parse(@json2), parse(json))
      parsed_json = parse(json)
      assert_equal(@hash, parsed_json)
      json = fast_generate({1=>2})
      assert_equal('{"1":2}', json)
      parsed_json = parse(json)
      assert_equal({"1"=>2}, parsed_json)
      assert_equal '666', fast_generate(666)
    end
  end

  def test_own_state
    state = State.new
    json = generate(@hash, state)
    assert_equal(parse(@json2), parse(json))
    parsed_json = parse(json)
    assert_equal(@hash, parsed_json)
    json = generate({1=>2}, state)
    assert_equal('{"1":2}', json)
    parsed_json = parse(json)
    assert_equal({"1"=>2}, parsed_json)
    assert_equal '666', generate(666, state)
  end

  def test_states
    json = generate({1=>2}, nil)
    assert_equal('{"1":2}', json)
    s = JSON.state.new
    assert s.check_circular?
    assert_deprecated_warning(/JSON::State/) do
      assert s[:check_circular?]
    end
    h = { 1=>2 }
    h[3] = h
    assert_raise(JSON::NestingError) {  generate(h) }
    assert_raise(JSON::NestingError) {  generate(h, s) }
    s = JSON.state.new
    a = [ 1, 2 ]
    a << a
    assert_raise(JSON::NestingError) {  generate(a, s) }
    assert s.check_circular?
    assert_deprecated_warning(/JSON::State/) do
      assert s[:check_circular?]
    end
  end

  def test_falsy_state
    object = { foo: [1, 2], bar: { egg: :spam }}
    expected_json = JSON.generate(
      object,
      array_nl:     "",
      indent:       "",
      object_nl:    "",
      space:        "",
      space_before: "",
    )

    assert_equal expected_json, JSON.generate(
      object,
      array_nl:     nil,
      indent:       nil,
      object_nl:    nil,
      space:        nil,
      space_before: nil,
    )
  end

  def test_state_defaults
    state = JSON::State.new
    assert_equal({
      :allow_nan             => false,
      :array_nl              => "",
      :as_json               => false,
      :ascii_only            => false,
      :buffer_initial_length => 1024,
      :depth                 => 0,
      :script_safe           => false,
      :strict                => false,
      :indent                => "",
      :max_nesting           => 100,
      :object_nl             => "",
      :space                 => "",
      :space_before          => "",
    }.sort_by { |n,| n.to_s }, state.to_h.sort_by { |n,| n.to_s })

    state = JSON::State.new(allow_duplicate_key: true)
    assert_equal({
      :allow_duplicate_key   => true,
      :allow_nan             => false,
      :array_nl              => "",
      :as_json               => false,
      :ascii_only            => false,
      :buffer_initial_length => 1024,
      :depth                 => 0,
      :script_safe           => false,
      :strict                => false,
      :indent                => "",
      :max_nesting           => 100,
      :object_nl             => "",
      :space                 => "",
      :space_before          => "",
    }.sort_by { |n,| n.to_s }, state.to_h.sort_by { |n,| n.to_s })
  end

  def test_allow_nan
    assert_deprecated_warning(/fast_generate/) do
      error = assert_raise(GeneratorError) { generate([JSON::NaN]) }
      assert_same JSON::NaN, error.invalid_object
      assert_equal '[NaN]', generate([JSON::NaN], :allow_nan => true)
      assert_raise(GeneratorError) { fast_generate([JSON::NaN]) }
      assert_raise(GeneratorError) { pretty_generate([JSON::NaN]) }
      assert_equal "[\n  NaN\n]", pretty_generate([JSON::NaN], :allow_nan => true)
      error = assert_raise(GeneratorError) { generate([JSON::Infinity]) }
      assert_same JSON::Infinity, error.invalid_object
      assert_equal '[Infinity]', generate([JSON::Infinity], :allow_nan => true)
      assert_raise(GeneratorError) { fast_generate([JSON::Infinity]) }
      assert_raise(GeneratorError) { pretty_generate([JSON::Infinity]) }
      assert_equal "[\n  Infinity\n]", pretty_generate([JSON::Infinity], :allow_nan => true)
      error = assert_raise(GeneratorError) { generate([JSON::MinusInfinity]) }
      assert_same JSON::MinusInfinity, error.invalid_object
      assert_equal '[-Infinity]', generate([JSON::MinusInfinity], :allow_nan => true)
      assert_raise(GeneratorError) { fast_generate([JSON::MinusInfinity]) }
      assert_raise(GeneratorError) { pretty_generate([JSON::MinusInfinity]) }
      assert_equal "[\n  -Infinity\n]", pretty_generate([JSON::MinusInfinity], :allow_nan => true)
    end
  end

  # An object that changes state.depth when it receives to_json(state)
  def bad_to_json
    obj = Object.new
    def obj.to_json(state)
      state.depth += 1
      "{#{state.object_nl}"\
        "#{state.indent * state.depth}\"foo\":#{state.space}1#{state.object_nl}"\
        "#{state.indent * (state.depth - 1)}}"
    end
    obj
  end

  def test_depth_restored_bad_to_json
    state = JSON::State.new
    state.generate(bad_to_json)
    assert_equal 0, state.depth
  end

  def test_depth_restored_bad_to_json_in_Array
    assert_equal <<~JSON.chomp, JSON.pretty_generate([bad_to_json] * 2)
      [
        {
          "foo": 1
        },
        {
          "foo": 1
        }
      ]
    JSON
    state = JSON::State.new
    state.generate([bad_to_json])
    assert_equal 0, state.depth
  end

  def test_depth_restored_bad_to_json_in_Hash
    assert_equal <<~JSON.chomp, JSON.pretty_generate(a: bad_to_json, b: bad_to_json)
      {
        "a": {
          "foo": 1
        },
        "b": {
          "foo": 1
        }
      }
    JSON
    state = JSON::State.new
    state.generate(a: bad_to_json)
    assert_equal 0, state.depth
  end

  def test_depth
    pretty = { object_nl: "\n", array_nl: "\n", space: " ", indent: "  " }
    state = JSON.state.new(**pretty)
    assert_equal %({\n  "foo": 42\n}), JSON.generate({ foo: 42 }, pretty)
    assert_equal %({\n  "foo": 42\n}), state.generate(foo: 42)
    state.depth = 1
    assert_equal %({\n    "foo": 42\n  }), JSON.generate({ foo: 42 }, pretty.merge(depth: 1))
    assert_equal %({\n    "foo": 42\n  }), state.generate(foo: 42)
  end

  def test_depth_nesting_error
    ary = []; ary << ary
    assert_raise(JSON::NestingError) { generate(ary) }
    assert_raise(JSON::NestingError) { JSON.pretty_generate(ary) }
  end

  def test_depth_nesting_error_to_json
    ary = []; ary << ary
    s = JSON.state.new(depth: 1)
    assert_raise(JSON::NestingError) { ary.to_json(s) }
    assert_equal 1, s.depth
  end

  def test_depth_nesting_error_Hash_to_json
    hash = {}; hash[:a] = hash
    s = JSON.state.new(depth: 1)
    assert_raise(JSON::NestingError) { hash.to_json(s) }
    assert_equal 1, s.depth
  end

  def test_depth_nesting_error_generate
    ary = []; ary << ary
    s = JSON.state.new(depth: 1)
    assert_raise(JSON::NestingError) { s.generate(ary) }
    assert_equal 1, s.depth
  end

  def test_depth_exception_calling_to_json
    def (obj = Object.new).to_json(*)
      raise
    end
    s = JSON.state.new(depth: 1).freeze
    assert_raise(RuntimeError) { s.generate([{ hash: obj }]) }
    assert_equal 1, s.depth
  end

  def test_buffer_initial_length
    s = JSON.state.new
    assert_equal 1024, s.buffer_initial_length
    s.buffer_initial_length = 0
    assert_equal 1024, s.buffer_initial_length
    s.buffer_initial_length = -1
    assert_equal 1024, s.buffer_initial_length
    s.buffer_initial_length = 128
    assert_equal 128, s.buffer_initial_length
  end

  def test_gc
    pid = fork do
      bignum_too_long_to_embed_as_string = 1234567890123456789012345
      expect = bignum_too_long_to_embed_as_string.to_s
      GC.stress = true

      10.times do |i|
        tmp = bignum_too_long_to_embed_as_string.to_json
        raise "#{expect}' is expected, but '#{tmp}'" unless tmp == expect
      end
    end
    _, status = Process.waitpid2(pid)
    assert_predicate status, :success?
  end if GC.respond_to?(:stress=) && Process.respond_to?(:fork)

  def test_configure_using_configure_and_merge
    numbered_state = {
      :indent       => "1",
      :space        => '2',
      :space_before => '3',
      :object_nl    => '4',
      :array_nl     => '5'
    }
    state1 = JSON.state.new
    state1.merge(numbered_state)
    assert_equal '1', state1.indent
    assert_equal '2', state1.space
    assert_equal '3', state1.space_before
    assert_equal '4', state1.object_nl
    assert_equal '5', state1.array_nl
    state2 = JSON.state.new
    state2.configure(numbered_state)
    assert_equal '1', state2.indent
    assert_equal '2', state2.space
    assert_equal '3', state2.space_before
    assert_equal '4', state2.object_nl
    assert_equal '5', state2.array_nl
  end

  def test_configure_hash_conversion
    state = JSON.state.new
    state.configure(:indent => '1')
    assert_equal '1', state.indent
    state = JSON.state.new
    foo = 'foo'.dup
    assert_raise(TypeError) do
      state.configure(foo)
    end
    def foo.to_h
      { indent: '2' }
    end
    state.configure(foo)
    assert_equal '2', state.indent
  end

  def test_broken_bignum # [ruby-core:38867]
    pid = fork do
      x = 1 << 64
      x.class.class_eval do
        def to_s
        end
      end
      begin
        JSON::Ext::Generator::State.new.generate(x)
        exit 1
      rescue TypeError
        exit 0
      end
    end
    _, status = Process.waitpid2(pid)
    assert status.success?
  rescue NotImplementedError
    # forking to avoid modifying core class of a parent process and
    # introducing race conditions of tests are run in parallel
  end

  def test_hash_likeness_set_symbol
    assert_deprecated_warning(/JSON::State/) do
      state = JSON.state.new
      assert_equal nil, state[:foo]
      assert_equal nil.class, state[:foo].class
      assert_equal nil, state['foo']
      state[:foo] = :bar
      assert_equal :bar, state[:foo]
      assert_equal :bar, state['foo']
      state_hash = state.to_hash
      assert_kind_of Hash, state_hash
      assert_equal :bar, state_hash[:foo]
    end
  end

  def test_hash_likeness_set_string
    assert_deprecated_warning(/JSON::State/) do
      state = JSON.state.new
      assert_equal nil, state[:foo]
      assert_equal nil, state['foo']
      state['foo'] = :bar
      assert_equal :bar, state[:foo]
      assert_equal :bar, state['foo']
      state_hash = state.to_hash
      assert_kind_of Hash, state_hash
      assert_equal :bar, state_hash[:foo]
    end
  end

  def test_json_state_to_h_roundtrip
    state = JSON.state.new
    assert_equal state.to_h, JSON.state.new(state.to_h).to_h
  end

  def test_json_generate
    assert_raise JSON::GeneratorError do
      generate(["\xea"])
    end
  end

  def test_json_generate_error_detailed_message
    error = assert_raise JSON::GeneratorError do
      generate(["\xea"])
    end

    assert_not_nil(error.detailed_message)
  end

  def test_json_generate_unsupported_types
    assert_raise JSON::GeneratorError do
      generate(Object.new, strict: true)
    end

    assert_raise JSON::GeneratorError do
      generate([Object.new], strict: true)
    end

    assert_raise JSON::GeneratorError do
      generate({ "key" => Object.new }, strict: true)
    end

    assert_raise JSON::GeneratorError do
      generate({ Object.new => "value" }, strict: true)
    end
  end

  def test_nesting
    too_deep = '[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[["Too deep"]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]'
    too_deep_ary = eval too_deep
    assert_raise(JSON::NestingError) { generate too_deep_ary }
    assert_raise(JSON::NestingError) { generate too_deep_ary, :max_nesting => 100 }
    ok = generate too_deep_ary, :max_nesting => 101
    assert_equal too_deep, ok
    ok = generate too_deep_ary, :max_nesting => nil
    assert_equal too_deep, ok
    ok = generate too_deep_ary, :max_nesting => false
    assert_equal too_deep, ok
    ok = generate too_deep_ary, :max_nesting => 0
    assert_equal too_deep, ok
  end

  def test_backslash
    data = [ '\\.(?i:gif|jpe?g|png)$' ]
    json = '["\\\\.(?i:gif|jpe?g|png)$"]'
    assert_equal json, generate(data)
    #
    data = [ '\\.(?i:gif|jpe?g|png)$\\.(?i:gif|jpe?g|png)$\\.(?i:gif|jpe?g|png)$\\.(?i:gif|jpe?g|png)$\\.(?i:gif|jpe?g|png)$\\.(?i:gif|jpe?g|png)$\\.(?i:gif|jpe?g|png)$\\.(?i:gif|jpe?g|png)$\\.(?i:gif|jpe?g|png)$\\.(?i:gif|jpe?g|png)$\\.(?i:gif|jpe?g|png)$' ]
    json = '["\\\\.(?i:gif|jpe?g|png)$\\\\.(?i:gif|jpe?g|png)$\\\\.(?i:gif|jpe?g|png)$\\\\.(?i:gif|jpe?g|png)$\\\\.(?i:gif|jpe?g|png)$\\\\.(?i:gif|jpe?g|png)$\\\\.(?i:gif|jpe?g|png)$\\\\.(?i:gif|jpe?g|png)$\\\\.(?i:gif|jpe?g|png)$\\\\.(?i:gif|jpe?g|png)$\\\\.(?i:gif|jpe?g|png)$"]'
    assert_equal json, generate(data)
    #
    data = [ '\\"\\"\\"\\"\\"\\"\\"\\"\\"\\"\\"' ]
    json = '["\\\\\"\\\\\"\\\\\"\\\\\"\\\\\"\\\\\"\\\\\"\\\\\"\\\\\"\\\\\"\\\\\""]'
    assert_equal json, generate(data)
    #
    data = [ '/' ]
    json = '["/"]'
    assert_equal json, generate(data)
    #
    data = [ '////////////////////////////////////////////////////////////////////////////////////' ]
    json = '["////////////////////////////////////////////////////////////////////////////////////"]'
    assert_equal json, generate(data)
    #
    data = [ '/' ]
    json = '["\/"]'
    assert_equal json, generate(data, :script_safe => true)
    #
    data = [ '///////////' ]
    json = '["\/\/\/\/\/\/\/\/\/\/\/"]'
    assert_equal json, generate(data, :script_safe => true)
    #
    data = [ '///////////////////////////////////////////////////////' ]
    json = '["\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/"]'
    assert_equal json, generate(data, :script_safe => true)
    #
    data = [ "\u2028\u2029" ]
    json = '["\u2028\u2029"]'
    assert_equal json, generate(data, :script_safe => true)
    #
    data = [ "ABC \u2028 DEF \u2029 GHI" ]
    json = '["ABC \u2028 DEF \u2029 GHI"]'
    assert_equal json, generate(data, :script_safe => true)
    #
    data = [ "/\u2028\u2029" ]
    json = '["\/\u2028\u2029"]'
    assert_equal json, generate(data, :escape_slash => true)
    #
    data = ['"']
    json = '["\""]'
    assert_equal json, generate(data)
    #
    data = ['"""""""""""""""""""""""""']
    json = '["\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\"\""]'
    assert_equal json, generate(data)
    #
    data = '"""""'
    json = '"\"\"\"\"\""'
    assert_equal json, generate(data)
    #
    data = "abc\n"
    json = '"abc\\n"'
    assert_equal json, generate(data)
    #
    data = "\nabc"
    json = '"\\nabc"'
    assert_equal json, generate(data)
    #
    data = ["'"]
    json = '["\\\'"]'
    assert_equal '["\'"]', generate(data)
    #
    data = ["倩", "瀨"]
    json = '["倩","瀨"]'
    assert_equal json, generate(data, script_safe: true)
    #
    data = '["This is a "test" of the emergency broadcast system."]'
    json = "\"[\\\"This is a \\\"test\\\" of the emergency broadcast system.\\\"]\""
    assert_equal json, generate(data)
    #
    data = '\tThis is a test of the emergency broadcast system.'
    json = "\"\\\\tThis is a test of the emergency broadcast system.\""
    assert_equal json, generate(data)
    #
    data = 'This\tis a test of the emergency broadcast system.'
    json = "\"This\\\\tis a test of the emergency broadcast system.\""
    assert_equal json, generate(data)
    #
    data = 'This is\ta test of the emergency broadcast system.'
    json = "\"This is\\\\ta test of the emergency broadcast system.\""
    assert_equal json, generate(data)
    #
    data = 'This is a test of the emergency broadcast\tsystem.'
    json = "\"This is a test of the emergency broadcast\\\\tsystem.\""
    assert_equal json, generate(data)
    #
    data = 'This is a test of the emergency broadcast\tsystem.\n'
    json = "\"This is a test of the emergency broadcast\\\\tsystem.\\\\n\""
    assert_equal json, generate(data)
    data = '"' * 15
    json = "\"\\\"\\\"\\\"\\\"\\\"\\\"\\\"\\\"\\\"\\\"\\\"\\\"\\\"\\\"\\\"\""
    assert_equal json, generate(data)
    data = "\"\"\"\"\"\"\"\"\"\"\"\"\"\"a"
    json = "\"\\\"\\\"\\\"\\\"\\\"\\\"\\\"\\\"\\\"\\\"\\\"\\\"\\\"\\\"a\""
    assert_equal json, generate(data)
    data = "\u0001\u0001\u0001\u0001"
    json = "\"\\u0001\\u0001\\u0001\\u0001\""
    assert_equal json, generate(data)
    data = "\u0001a\u0001a\u0001a\u0001a"
    json = "\"\\u0001a\\u0001a\\u0001a\\u0001a\""
    assert_equal json, generate(data)
    data = "\u0001aa\u0001aa"
    json = "\"\\u0001aa\\u0001aa\""
    assert_equal json, generate(data)
    data = "\u0001aa\u0001aa\u0001aa"
    json = "\"\\u0001aa\\u0001aa\\u0001aa\""
    assert_equal json, generate(data)
    data = "\u0001aa\u0001aa\u0001aa\u0001aa\u0001aa\u0001aa"
    json = "\"\\u0001aa\\u0001aa\\u0001aa\\u0001aa\\u0001aa\\u0001aa\""
    assert_equal json, generate(data)
    data = "\u0001a\u0002\u0001a\u0002\u0001a\u0002\u0001a\u0002\u0001a\u0002\u0001a\u0002\u0001a\u0002\u0001a\u0002"
    json = "\"\\u0001a\\u0002\\u0001a\\u0002\\u0001a\\u0002\\u0001a\\u0002\\u0001a\\u0002\\u0001a\\u0002\\u0001a\\u0002\\u0001a\\u0002\""
    assert_equal json, generate(data)
    data = "ab\u0002c"
    json = "\"ab\\u0002c\""
    assert_equal json, generate(data)
    data = "ab\u0002cab\u0002cab\u0002cab\u0002c"
    json = "\"ab\\u0002cab\\u0002cab\\u0002cab\\u0002c\""
    assert_equal json, generate(data)
    data = "ab\u0002cab\u0002cab\u0002cab\u0002cab\u0002cab\u0002c"
    json = "\"ab\\u0002cab\\u0002cab\\u0002cab\\u0002cab\\u0002cab\\u0002c\""
    assert_equal json, generate(data)
    data = "\n\t\f\b\n\t\f\b\n\t\f\b\n\t\f"
    json = "\"\\n\\t\\f\\b\\n\\t\\f\\b\\n\\t\\f\\b\\n\\t\\f\""
    assert_equal json, generate(data)
    data = "\n\t\f\b\n\t\f\b\n\t\f\b\n\t\f\b"
    json = "\"\\n\\t\\f\\b\\n\\t\\f\\b\\n\\t\\f\\b\\n\\t\\f\\b\""
    assert_equal json, generate(data)
    data = "a\n\t\f\b\n\t\f\b\n\t\f\b\n\t"
    json = "\"a\\n\\t\\f\\b\\n\\t\\f\\b\\n\\t\\f\\b\\n\\t\""
    assert_equal json, generate(data)
  end

  def test_string_subclass
    s = Class.new(String) do
      def to_s; self; end
      undef to_json
    end
    assert_nothing_raised(SystemStackError) do
      assert_equal '["foo"]', JSON.generate([s.new('foo')])
    end
  end

  def test_invalid_encoding_string
    error = assert_raise(JSON::GeneratorError) do
      "\x82\xAC\xEF".to_json
    end
    assert_includes error.message, "source sequence is illegal/malformed utf-8"

    error = assert_raise(JSON::GeneratorError) do
      JSON.dump("\x82\xAC\xEF")
    end
    assert_includes error.message, "source sequence is illegal/malformed utf-8"

    assert_raise(JSON::GeneratorError) do
      JSON.dump("\x82\xAC\xEF".b)
    end

    assert_raise(JSON::GeneratorError) do
      "\x82\xAC\xEF".b.to_json
    end

    assert_raise(JSON::GeneratorError) do
      ["\x82\xAC\xEF".b].to_json
    end

    badly_encoded = "\x82\xAC\xEF".b
    exception = assert_raise(JSON::GeneratorError) do
      { foo: badly_encoded }.to_json
    end

    assert_kind_of EncodingError, exception.cause
    assert_same badly_encoded, exception.invalid_object
  end

  class MyCustomString < String
    def to_json(_state = nil)
      '"my_custom_key"'
    end

    def to_s
      self
    end
  end

  def test_string_subclass_as_keys
    # Ref: https://github.com/ruby/json/issues/667
    # if key.to_s doesn't return a bare string, we call `to_json` on it.
    key = MyCustomString.new("won't be used")
    assert_equal '{"my_custom_key":1}', JSON.generate(key => 1)
  end

  class FakeString
    def to_json(_state = nil)
      raise "Shouldn't be called"
    end

    def to_s
      self
    end
  end

  def test_custom_object_as_keys
    key = FakeString.new
    error = assert_raise(TypeError) do
      JSON.generate(key => 1)
    end
    assert_match "FakeString", error.message
  end

  def test_to_json_called_with_state_object
    object = Object.new
    called = false
    argument = nil
    object.singleton_class.define_method(:to_json) do |state|
      called = true
      argument = state
      "<hello>"
    end

    assert_equal "<hello>", JSON.dump(object)
    assert called, "#to_json wasn't called"
    assert_instance_of JSON::State, argument
  end

  module CustomToJSON
    def to_json(*)
      %{"#{self.class.name}#to_json"}
    end
  end

  module CustomToS
    def to_s
      "#{self.class.name}#to_s"
    end
  end

  class ArrayWithToJSON < Array
    include CustomToJSON
  end

  def test_array_subclass_with_to_json
    assert_equal '["JSONGeneratorTest::ArrayWithToJSON#to_json"]', JSON.generate([ArrayWithToJSON.new])
    assert_equal '{"[]":1}', JSON.generate(ArrayWithToJSON.new => 1)
  end

  class ArrayWithToS < Array
    include CustomToS
  end

  def test_array_subclass_with_to_s
    assert_equal '[[]]', JSON.generate([ArrayWithToS.new])
    assert_equal '{"JSONGeneratorTest::ArrayWithToS#to_s":1}', JSON.generate(ArrayWithToS.new => 1)
  end

  class HashWithToJSON < Hash
    include CustomToJSON
  end

  def test_hash_subclass_with_to_json
    assert_equal '["JSONGeneratorTest::HashWithToJSON#to_json"]', JSON.generate([HashWithToJSON.new])
    assert_equal '{"{}":1}', JSON.generate(HashWithToJSON.new => 1)
  end

  class HashWithToS < Hash
    include CustomToS
  end

  def test_hash_subclass_with_to_s
    assert_equal '[{}]', JSON.generate([HashWithToS.new])
    assert_equal '{"JSONGeneratorTest::HashWithToS#to_s":1}', JSON.generate(HashWithToS.new => 1)
  end

  class StringWithToJSON < String
    include CustomToJSON
  end

  def test_string_subclass_with_to_json
    assert_equal '["JSONGeneratorTest::StringWithToJSON#to_json"]', JSON.generate([StringWithToJSON.new])
    assert_equal '{"":1}', JSON.generate(StringWithToJSON.new => 1)
  end

  class StringWithToS < String
    include CustomToS
  end

  def test_string_subclass_with_to_s
    assert_equal '[""]', JSON.generate([StringWithToS.new])
    assert_equal '{"JSONGeneratorTest::StringWithToS#to_s":1}', JSON.generate(StringWithToS.new => 1)
  end

  def test_string_subclass_with_broken_to_s
    klass = Class.new(String) do
      def to_s
        false
      end
    end
    s = klass.new("test")
    assert_equal '["test"]', JSON.generate([s])

    omit("Can't figure out how to match behavior in java code") if RUBY_PLATFORM == "java"

    assert_raise TypeError do
      JSON.generate(s => 1)
    end
  end

  if defined?(JSON::Ext::Generator) and RUBY_PLATFORM != "java"
    def test_valid_utf8_in_different_encoding
      utf8_string = "€™"
      wrong_encoding_string = utf8_string.b
      # This behavior is historical. Not necessary desirable. We should deprecated it.
      # The pure and java version of the gem already don't behave this way.
      assert_warning(/UTF-8 string passed as BINARY, this will raise an encoding error in json 3.0/) do
        assert_equal utf8_string.to_json, wrong_encoding_string.to_json
      end

      assert_warning(/UTF-8 string passed as BINARY, this will raise an encoding error in json 3.0/) do
        assert_equal JSON.dump(utf8_string), JSON.dump(wrong_encoding_string)
      end
    end

    def test_string_ext_included_calls_super
      included = false

      Module.send(:alias_method, :included_orig, :included)
      Module.send(:remove_method, :included)
      Module.send(:define_method, :included) do |base|
        included_orig(base)
        included = true
      end

      Class.new(String) do
        include JSON::Ext::Generator::GeneratorMethods::String
      end

      assert included
    ensure
      if Module.private_method_defined?(:included_orig)
        Module.send(:remove_method, :included) if Module.method_defined?(:included)
        Module.send(:alias_method, :included, :included_orig)
        Module.send(:remove_method, :included_orig)
      end
    end
  end

  def test_nonutf8_encoding
    assert_equal("\"5\u{b0}\"", "5\xb0".dup.force_encoding(Encoding::ISO_8859_1).to_json)
  end

  def test_utf8_multibyte
    assert_equal('["foßbar"]', JSON.generate(["foßbar"]))
    assert_equal('"n€ßt€ð2"', JSON.generate("n€ßt€ð2"))
    assert_equal('"\"\u0000\u001f"', JSON.generate("\"\u0000\u001f"))
  end

  def test_fragment
    fragment = JSON::Fragment.new(" 42")
    assert_equal '{"number": 42}', JSON.generate({ number: fragment })
    assert_equal '{"number": 42}', JSON.generate({ number: fragment }, strict: true)
  end

  def test_json_generate_as_json_convert_to_proc
    object = Object.new
    assert_equal object.object_id.to_json, JSON.generate(object, strict: true, as_json: -> (o, is_key) { o.object_id })
  end

  def test_as_json_nan_does_not_call_to_json
    def (obj = Object.new).to_json(*)
      "null"
    end
    assert_raise(JSON::GeneratorError) do
      JSON.generate(Float::NAN, strict: true, as_json: proc { obj })
    end
  end

  def assert_float_roundtrip(expected, actual)
    assert_equal(expected, JSON.generate(actual))
    assert_equal(actual, JSON.parse(JSON.generate(actual)), "JSON: #{JSON.generate(actual)}")
  end

  def test_json_generate_float
    assert_float_roundtrip "-1.0", -1.0
    assert_float_roundtrip "1.0", 1.0
    assert_float_roundtrip "0.0", 0.0
    assert_float_roundtrip "12.2", 12.2
    assert_float_roundtrip "2.34375", 7.5 / 3.2
    assert_float_roundtrip "12.0", 12.0
    assert_float_roundtrip "100.0", 100.0
    assert_float_roundtrip "1000.0", 1000.0

    if RUBY_ENGINE == "jruby"
      assert_float_roundtrip "1.7468619377842371E9", 1746861937.7842371
    else
      assert_float_roundtrip "1746861937.7842371", 1746861937.7842371
    end

    if RUBY_ENGINE == "ruby"
      assert_float_roundtrip "100000000000000.0", 100000000000000.0
      assert_float_roundtrip "1e+15", 1e+15
      assert_float_roundtrip "-100000000000000.0", -100000000000000.0
      assert_float_roundtrip "-1e+15", -1e+15
      assert_float_roundtrip "1111111111111111.1", 1111111111111111.1
      assert_float_roundtrip "1.1111111111111112e+16", 11111111111111111.1
      assert_float_roundtrip "-1111111111111111.1", -1111111111111111.1
      assert_float_roundtrip "-1.1111111111111112e+16", -11111111111111111.1

      assert_float_roundtrip "-0.000000022471348024634545", -2.2471348024634545e-08
      assert_float_roundtrip "-0.0000000022471348024634545", -2.2471348024634545e-09
      assert_float_roundtrip "-2.2471348024634546e-10", -2.2471348024634545e-10
    end
  end

  def test_numbers_of_various_sizes
    numbers = [
      0, 1, -1, 9, -9, 13, -13, 91, -91, 513, -513, 7513, -7513,
      17591, -17591, -4611686018427387904, 4611686018427387903,
      2**62, 2**63, 2**64, -(2**62), -(2**63), -(2**64)
    ]

    numbers.each do |number|
      assert_equal "[#{number}]", JSON.generate([number])
    end
  end

  def test_generate_duplicate_keys_allowed
    hash = { foo: 1, "foo" => 2 }
    assert_equal %({"foo":1,"foo":2}), JSON.generate(hash, allow_duplicate_key: true)
  end

  def test_generate_duplicate_keys_deprecated
    hash = { foo: 1, "foo" => 2 }
    assert_deprecated_warning(/allow_duplicate_key/) do
      assert_equal %({"foo":1,"foo":2}), JSON.generate(hash)
    end
  end

  def test_generate_duplicate_keys_disallowed
    hash = { foo: 1, "foo" => 2 }
    error = assert_raise JSON::GeneratorError do
      JSON.generate(hash, allow_duplicate_key: false)
    end
    assert_equal %(detected duplicate key "foo" in #{hash.inspect}), error.message
  end

  def test_frozen
    state = JSON::State.new.freeze
    assert_raise(FrozenError) do
      state.configure(max_nesting: 1)
    end
    setters = state.methods.grep(/\w=$/)
    assert_not_empty setters
    setters.each do |setter|
      assert_raise(FrozenError) do
        state.send(setter, 1)
      end
    end
  end

  # The case when the State is frozen is tested in JSONCoderTest#test_nesting_recovery
  def test_nesting_recovery
    state = JSON::State.new
    ary = []
    ary << ary
    assert_raise(JSON::NestingError) { state.generate(ary) }
    assert_equal 0, state.depth
    assert_equal '{"a":1}', state.generate({ a: 1 })
  end
end
