#!/usr/bin/env ruby
# frozen_string_literal: false

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
  end

  def test_generate_pretty
    json = pretty_generate({})
    assert_equal(<<'EOT'.chomp, json)
{
}
EOT
    json = pretty_generate(@hash)
    # hashes aren't (insertion) ordered on every ruby implementation
    # assert_equal(@json3, json)
    assert_equal(parse(@json3), parse(json))
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
    assert_equal '666', pretty_generate(666)
  end

  def test_generate_custom
    state = State.new(:space_before => " ", :space => "   ", :indent => "<i>", :object_nl => "\n", :array_nl => "<a_nl>")
    json = generate({1=>{2=>3,4=>[5,6]}}, state)
    assert_equal(<<'EOT'.chomp, json)
{
<i>"1" :   {
<i><i>"2" :   3,
<i><i>"4" :   [<a_nl><i><i><i>5,<a_nl><i><i><i>6<a_nl><i><i>]
<i>}
}
EOT
  end

  def test_fast_generate
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
    assert s[:check_circular?]
    h = { 1=>2 }
    h[3] = h
    assert_raise(JSON::NestingError) {  generate(h) }
    assert_raise(JSON::NestingError) {  generate(h, s) }
    s = JSON.state.new
    a = [ 1, 2 ]
    a << a
    assert_raise(JSON::NestingError) {  generate(a, s) }
    assert s.check_circular?
    assert s[:check_circular?]
  end

  def test_pretty_state
    state = JSON.create_pretty_state
    assert_equal({
      :allow_nan             => false,
      :array_nl              => "\n",
      :ascii_only            => false,
      :buffer_initial_length => 1024,
      :depth                 => 0,
      :script_safe           => false,
      :strict                => false,
      :indent                => "  ",
      :max_nesting           => 100,
      :object_nl             => "\n",
      :space                 => " ",
      :space_before          => "",
    }.sort_by { |n,| n.to_s }, state.to_h.sort_by { |n,| n.to_s })
  end

  def test_safe_state
    state = JSON::State.new
    assert_equal({
      :allow_nan             => false,
      :array_nl              => "",
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

  def test_fast_state
    state = JSON.create_fast_state
    assert_equal({
      :allow_nan             => false,
      :array_nl              => "",
      :ascii_only            => false,
      :buffer_initial_length => 1024,
      :depth                 => 0,
      :script_safe           => false,
      :strict                => false,
      :indent                => "",
      :max_nesting           => 0,
      :object_nl             => "",
      :space                 => "",
      :space_before          => "",
    }.sort_by { |n,| n.to_s }, state.to_h.sort_by { |n,| n.to_s })
  end

  def test_allow_nan
    assert_raise(GeneratorError) { generate([JSON::NaN]) }
    assert_equal '[NaN]', generate([JSON::NaN], :allow_nan => true)
    assert_raise(GeneratorError) { fast_generate([JSON::NaN]) }
    assert_raise(GeneratorError) { pretty_generate([JSON::NaN]) }
    assert_equal "[\n  NaN\n]", pretty_generate([JSON::NaN], :allow_nan => true)
    assert_raise(GeneratorError) { generate([JSON::Infinity]) }
    assert_equal '[Infinity]', generate([JSON::Infinity], :allow_nan => true)
    assert_raise(GeneratorError) { fast_generate([JSON::Infinity]) }
    assert_raise(GeneratorError) { pretty_generate([JSON::Infinity]) }
    assert_equal "[\n  Infinity\n]", pretty_generate([JSON::Infinity], :allow_nan => true)
    assert_raise(GeneratorError) { generate([JSON::MinusInfinity]) }
    assert_equal '[-Infinity]', generate([JSON::MinusInfinity], :allow_nan => true)
    assert_raise(GeneratorError) { fast_generate([JSON::MinusInfinity]) }
    assert_raise(GeneratorError) { pretty_generate([JSON::MinusInfinity]) }
    assert_equal "[\n  -Infinity\n]", pretty_generate([JSON::MinusInfinity], :allow_nan => true)
  end

  def test_depth
    ary = []; ary << ary
    assert_raise(JSON::NestingError) { generate(ary) }
    assert_raise(JSON::NestingError) { JSON.pretty_generate(ary) }
    s = JSON.state.new
    assert_equal 0, s.depth
    assert_raise(JSON::NestingError) { ary.to_json(s) }
    assert_equal 100, s.depth
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
    if respond_to?(:assert_in_out_err) && !(RUBY_PLATFORM =~ /java/)
      assert_in_out_err(%w[-rjson], <<-EOS, [], [])
        bignum_too_long_to_embed_as_string = 1234567890123456789012345
        expect = bignum_too_long_to_embed_as_string.to_s
        GC.stress = true

        10.times do |i|
          tmp = bignum_too_long_to_embed_as_string.to_json
          raise "'\#{expect}' is expected, but '\#{tmp}'" unless tmp == expect
        end
      EOS
    end
  end if GC.respond_to?(:stress=)

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
    foo = 'foo'
    assert_raise(TypeError) do
      state.configure(foo)
    end
    def foo.to_h
      { :indent => '2' }
    end
    state.configure(foo)
    assert_equal '2', state.indent
  end

  if defined?(JSON::Ext::Generator)
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
  end

  def test_hash_likeness_set_symbol
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

  def test_hash_likeness_set_string
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

  def test_json_generate
    assert_raise JSON::GeneratorError do
      generate(["\xea"])
    end
  end

  def test_json_generate_unsupported_types
    assert_raise JSON::GeneratorError do
      generate(Object.new, strict: true)
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
    data = [ '\\"' ]
    json = '["\\\\\""]'
    assert_equal json, generate(data)
    #
    data = [ '/' ]
    json = '["/"]'
    assert_equal json, generate(data)
    #
    data = [ '/' ]
    json = '["\/"]'
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
    data = ["'"]
    json = '["\\\'"]'
    assert_equal '["\'"]', generate(data)
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

  if defined?(JSON::Ext::Generator) and RUBY_PLATFORM != "java"
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

  if defined?(Encoding)
    def test_nonutf8_encoding
      assert_equal("\"5\u{b0}\"", "5\xb0".force_encoding("iso-8859-1").to_json)
    end
  end
end
