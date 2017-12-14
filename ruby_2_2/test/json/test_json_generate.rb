#!/usr/bin/env ruby
# encoding: utf-8

require 'test/unit'
require File.join(File.dirname(__FILE__), 'setup_variant')

class TestJSONGenerate < Test::Unit::TestCase
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

  def test_generate
    json = generate(@hash)
    assert_equal(JSON.parse(@json2), JSON.parse(json))
    json = JSON[@hash]
    assert_equal(JSON.parse(@json2), JSON.parse(json))
    parsed_json = parse(json)
    assert_equal(@hash, parsed_json)
    json = generate({1=>2})
    assert_equal('{"1":2}', json)
    parsed_json = parse(json)
    assert_equal({"1"=>2}, parsed_json)
    assert_raise(GeneratorError) { generate(666) }
    assert_equal '666', generate(666, :quirks_mode => true)
  end

  def test_generate_pretty
    json = pretty_generate(@hash)
    # hashes aren't (insertion) ordered on every ruby implementation assert_equal(@json3, json)
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
    assert_raise(GeneratorError) { pretty_generate(666) }
    assert_equal '666', pretty_generate(666, :quirks_mode => true)
  end

  def test_fast_generate
    json = fast_generate(@hash)
    assert_equal(JSON.parse(@json2), JSON.parse(json))
    parsed_json = parse(json)
    assert_equal(@hash, parsed_json)
    json = fast_generate({1=>2})
    assert_equal('{"1":2}', json)
    parsed_json = parse(json)
    assert_equal({"1"=>2}, parsed_json)
    assert_raise(GeneratorError) { fast_generate(666) }
    assert_equal '666', fast_generate(666, :quirks_mode => true)
  end

  def test_own_state
    state = State.new
    json = generate(@hash, state)
    assert_equal(JSON.parse(@json2), JSON.parse(json))
    parsed_json = parse(json)
    assert_equal(@hash, parsed_json)
    json = generate({1=>2}, state)
    assert_equal('{"1":2}', json)
    parsed_json = parse(json)
    assert_equal({"1"=>2}, parsed_json)
    assert_raise(GeneratorError) { generate(666, state) }
    state.quirks_mode = true
    assert state.quirks_mode?
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
    assert_raises(JSON::NestingError) {  generate(h) }
    assert_raises(JSON::NestingError) {  generate(h, s) }
    s = JSON.state.new
    a = [ 1, 2 ]
    a << a
    assert_raises(JSON::NestingError) {  generate(a, s) }
    assert s.check_circular?
    assert s[:check_circular?]
  end

  def test_pretty_state
    state = PRETTY_STATE_PROTOTYPE.dup
    assert_equal({
      :allow_nan             => false,
      :array_nl              => "\n",
      :ascii_only            => false,
      :buffer_initial_length => 1024,
      :quirks_mode           => false,
      :depth                 => 0,
      :indent                => "  ",
      :max_nesting           => 100,
      :object_nl             => "\n",
      :space                 => " ",
      :space_before          => "",
    }.sort_by { |n,| n.to_s }, state.to_h.sort_by { |n,| n.to_s })
  end

  def test_safe_state
    state = SAFE_STATE_PROTOTYPE.dup
    assert_equal({
      :allow_nan             => false,
      :array_nl              => "",
      :ascii_only            => false,
      :buffer_initial_length => 1024,
      :quirks_mode           => false,
      :depth                 => 0,
      :indent                => "",
      :max_nesting           => 100,
      :object_nl             => "",
      :space                 => "",
      :space_before          => "",
    }.sort_by { |n,| n.to_s }, state.to_h.sort_by { |n,| n.to_s })
  end

  def test_fast_state
    state = FAST_STATE_PROTOTYPE.dup
    assert_equal({
      :allow_nan             => false,
      :array_nl              => "",
      :ascii_only            => false,
      :buffer_initial_length => 1024,
      :quirks_mode           => false,
      :depth                 => 0,
      :indent                => "",
      :max_nesting           => 0,
      :object_nl             => "",
      :space                 => "",
      :space_before          => "",
    }.sort_by { |n,| n.to_s }, state.to_h.sort_by { |n,| n.to_s })
  end

  def test_allow_nan
    assert_raises(GeneratorError) { generate([JSON::NaN]) }
    assert_equal '[NaN]', generate([JSON::NaN], :allow_nan => true)
    assert_raises(GeneratorError) { fast_generate([JSON::NaN]) }
    assert_raises(GeneratorError) { pretty_generate([JSON::NaN]) }
    assert_equal "[\n  NaN\n]", pretty_generate([JSON::NaN], :allow_nan => true)
    assert_raises(GeneratorError) { generate([JSON::Infinity]) }
    assert_equal '[Infinity]', generate([JSON::Infinity], :allow_nan => true)
    assert_raises(GeneratorError) { fast_generate([JSON::Infinity]) }
    assert_raises(GeneratorError) { pretty_generate([JSON::Infinity]) }
    assert_equal "[\n  Infinity\n]", pretty_generate([JSON::Infinity], :allow_nan => true)
    assert_raises(GeneratorError) { generate([JSON::MinusInfinity]) }
    assert_equal '[-Infinity]', generate([JSON::MinusInfinity], :allow_nan => true)
    assert_raises(GeneratorError) { fast_generate([JSON::MinusInfinity]) }
    assert_raises(GeneratorError) { pretty_generate([JSON::MinusInfinity]) }
    assert_equal "[\n  -Infinity\n]", pretty_generate([JSON::MinusInfinity], :allow_nan => true)
  end

  def test_depth
    ary = []; ary << ary
    assert_equal 0, JSON::SAFE_STATE_PROTOTYPE.depth
    assert_raises(JSON::NestingError) { JSON.generate(ary) }
    assert_equal 0, JSON::SAFE_STATE_PROTOTYPE.depth
    assert_equal 0, JSON::PRETTY_STATE_PROTOTYPE.depth
    assert_raises(JSON::NestingError) { JSON.pretty_generate(ary) }
    assert_equal 0, JSON::PRETTY_STATE_PROTOTYPE.depth
    s = JSON.state.new
    assert_equal 0, s.depth
    assert_raises(JSON::NestingError) { ary.to_json(s) }
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
    assert_in_out_err(%w[-rjson --disable-gems], <<-EOS, [], [])
      bignum_too_long_to_embed_as_string = 1234567890123456789012345
      expect = bignum_too_long_to_embed_as_string.to_s
      GC.stress = true

      10.times do |i|
        tmp = bignum_too_long_to_embed_as_string.to_json
        raise "'\#{expect}' is expected, but '\#{tmp}'" unless tmp == expect
      end
    EOS
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
        Bignum.class_eval do
          def to_s
          end
        end
        begin
          JSON::Ext::Generator::State.new.generate(1<<64)
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
      assert_equal true, JSON.generate(["\xea"])
    end
  end
end
