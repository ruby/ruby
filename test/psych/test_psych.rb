# frozen_string_literal: true
require_relative 'helper'

require 'stringio'
require 'tempfile'

class TestPsych < Psych::TestCase

  def setup
    @orig_verbose, $VERBOSE = $VERBOSE, nil
  end

  def teardown
    Psych.domain_types.clear
    $VERBOSE = @orig_verbose
  end

  def test_line_width_invalid
    assert_raise(ArgumentError) { Psych.dump('x', { :line_width => -2 }) }
  end

  def test_line_width_no_limit
    data = { 'a' => 'a b' * 50}
    expected = "---\na: #{'a b' * 50}\n"
    assert_equal(expected, Psych.dump(data, { :line_width => -1 }))
  end

  def test_line_width_limit
    yml = Psych.dump('123456 7', { :line_width => 5 })
    assert_match(/^\s*7/, yml)
  end

  def test_indent
    yml = Psych.dump({:a => {'b' => 'c'}}, {:indentation => 5})
    assert_match(/^[ ]{5}b/, yml)
  end

  def test_canonical
    yml = Psych.dump({:a => {'b' => 'c'}}, {:canonical => true})
    assert_match(/\? "b/, yml)
  end

  def test_header
    yml = Psych.dump({:a => {'b' => 'c'}}, {:header => true})
    assert_match(/YAML/, yml)
  end

  def test_version_array
    yml = Psych.dump({:a => {'b' => 'c'}}, {:version => [1,1]})
    assert_match(/1.1/, yml)
  end

  def test_version_string
    yml = Psych.dump({:a => {'b' => 'c'}}, {:version => '1.1'})
    assert_match(/1.1/, yml)
  end

  def test_version_bool
    yml = Psych.dump({:a => {'b' => 'c'}}, {:version => true})
    assert_match(/1.1/, yml)
  end

  def test_load_argument_error
    assert_raise(TypeError) do
      Psych.load nil
    end
  end

  def test_parse
    assert_equal %w[a b], Psych.parse("- a\n- b").to_ruby
  end

  def test_parse_default_fallback
    assert_equal false, Psych.parse("")
  end

  def test_parse_raises_on_bad_input
    assert_raise(Psych::SyntaxError) { Psych.parse("--- `") }
  end

  def test_non_existing_class_on_deserialize
    e = assert_raise(ArgumentError) do
      Psych.unsafe_load("--- !ruby/object:NonExistent\nfoo: 1")
    end
    assert_equal 'undefined class/module NonExistent', e.message
  end

  def test_dump_stream
    things = [22, "foo \n", {}]
    stream = Psych.dump_stream(*things)
    assert_equal things, Psych.load_stream(stream)
  end

  def test_dump_file
    hash = {'hello' => 'TGIF!'}
    Tempfile.create('fun.yml') do |io|
      assert_equal io, Psych.dump(hash, io)
      io.rewind
      assert_equal Psych.dump(hash), io.read
    end
  end

  def test_dump_io
    hash = {'hello' => 'TGIF!'}
    stringio = StringIO.new ''.dup
    assert_equal stringio, Psych.dump(hash, stringio)
    assert_equal Psych.dump(hash), stringio.string
  end

  def test_simple
    assert_equal 'foo', Psych.load("--- foo\n")
  end

  def test_libyaml_version
    assert Psych.libyaml_version
    assert_equal Psych.libyaml_version.join('.'), Psych::LIBYAML_VERSION
  end

  def test_load_stream
    docs = Psych.load_stream("--- foo\n...\n--- bar\n...")
    assert_equal %w{ foo bar }, docs
  end

  def test_load_stream_freeze
    docs = Psych.load_stream("--- foo\n...\n--- bar\n...", freeze: true)
    assert_equal %w{ foo bar }, docs
    docs.each do |string|
      assert_predicate string, :frozen?
    end
  end

  def test_load_stream_symbolize_names
    docs = Psych.load_stream("---\nfoo: bar", symbolize_names: true)
    assert_equal [{foo: 'bar'}], docs
  end

  def test_load_stream_default_fallback
    assert_equal [], Psych.load_stream("")
  end

  def test_load_stream_raises_on_bad_input
    assert_raise(Psych::SyntaxError) { Psych.load_stream("--- `") }
  end

  def test_parse_stream
    docs = Psych.parse_stream("--- foo\n...\n--- bar\n...")
    assert_equal(%w[foo bar], docs.children.map(&:transform))
  end

  def test_parse_stream_with_block
    docs = []
    Psych.parse_stream("--- foo\n...\n--- bar\n...") do |node|
      docs << node
    end

    assert_equal %w[foo bar], docs.map(&:to_ruby)
  end

  def test_parse_stream_default_fallback
    docs = Psych.parse_stream("")
    assert_equal [], docs.children.map(&:to_ruby)
  end

  def test_parse_stream_with_block_default_fallback
    docs = []
    Psych.parse_stream("") do |node|
      docs << node
    end

    assert_equal [], docs.map(&:to_ruby)
  end

  def test_parse_stream_raises_on_bad_input
    assert_raise(Psych::SyntaxError) { Psych.parse_stream("--- `") }
  end

  def test_add_builtin_type
    got = nil
    Psych.add_builtin_type 'omap' do |type, val|
      got = val
    end
    Psych.load('--- !!omap hello')
    assert_equal 'hello', got
  ensure
    Psych.remove_type 'omap'
  end

  def test_domain_types
    got = nil
    Psych.add_domain_type 'foo.bar/2002', 'foo' do |type, val|
      got = val
    end

    Psych.load('--- !foo.bar/2002:foo hello')
    assert_equal 'hello', got

    Psych.load("--- !foo.bar/2002:foo\n- hello\n- world")
    assert_equal %w{ hello world }, got

    Psych.load("--- !foo.bar/2002:foo\nhello: world")
    assert_equal({ 'hello' => 'world' }, got)
  end

  def test_load_freeze
    data = Psych.load("--- {foo: ['a']}", freeze: true)
    assert_predicate data, :frozen?
    assert_predicate data['foo'], :frozen?
    assert_predicate data['foo'].first, :frozen?
  end

  def test_load_freeze_deduplication
    unless String.method_defined?(:-@) && (-("a" * 20)).equal?((-("a" * 20)))
      pend "This Ruby implementation doesn't support string deduplication"
    end

    data = Psych.load("--- ['a']", freeze: true)
    assert_same 'a', data.first
  end

  def test_load_default_fallback
    assert_equal false, Psych.unsafe_load("")
  end

  def test_load_with_fallback
    assert_equal 42, Psych.load("", filename: "file", fallback: 42)
  end

  def test_load_with_fallback_nil_or_false
    assert_nil Psych.load("", filename: "file", fallback: nil)
    assert_equal false, Psych.load("", filename: "file", fallback: false)
  end

  def test_load_with_fallback_hash
    assert_equal Hash.new, Psych.load("", filename: "file", fallback: Hash.new)
  end

  def test_load_with_fallback_for_nil
    assert_nil Psych.unsafe_load("--- null", filename: "file", fallback: 42)
  end

  def test_load_with_fallback_for_false
    assert_equal false, Psych.unsafe_load("--- false", filename: "file", fallback: 42)
  end

  def test_load_file
    Tempfile.create(['yikes', 'yml']) {|t|
      t.binmode
      t.write('--- hello world')
      t.close
      assert_equal 'hello world', Psych.load_file(t.path)
    }
  end

  def test_load_file_freeze
    Tempfile.create(['yikes', 'yml']) {|t|
      t.binmode
      t.write('--- hello world')
      t.close

      object = Psych.load_file(t.path, freeze: true)
      assert_predicate object, :frozen?
    }
  end

  def test_load_file_symbolize_names
    Tempfile.create(['yikes', 'yml']) {|t|
      t.binmode
      t.write("---\nfoo: bar")
      t.close

      assert_equal({foo: 'bar'}, Psych.load_file(t.path, symbolize_names: true))
    }
  end

  def test_load_file_default_fallback
    Tempfile.create(['empty', 'yml']) {|t|
      assert_equal false, Psych.unsafe_load_file(t.path)
    }
  end

  def test_load_file_with_fallback
    Tempfile.create(['empty', 'yml']) {|t|
      assert_equal 42, Psych.load_file(t.path, fallback: 42)
    }
  end

  def test_load_file_with_fallback_nil_or_false
    Tempfile.create(['empty', 'yml']) {|t|
      assert_nil Psych.load_file(t.path, fallback: nil)
      assert_equal false, Psych.load_file(t.path, fallback: false)
    }
  end

  def test_load_file_with_fallback_hash
    Tempfile.create(['empty', 'yml']) {|t|
      assert_equal Hash.new, Psych.load_file(t.path, fallback: Hash.new)
    }
  end

  def test_load_file_with_fallback_for_nil
    Tempfile.create(['nil', 'yml']) {|t|
      t.binmode
      t.write('--- null')
      t.close
      assert_nil Psych.load_file(t.path, fallback: 42)
    }
  end

  def test_load_file_with_fallback_for_false
    Tempfile.create(['false', 'yml']) {|t|
      t.binmode
      t.write('--- false')
      t.close
      assert_equal false, Psych.load_file(t.path, fallback: 42)
    }
  end

  def test_safe_load_file_with_permitted_classe
    Tempfile.create(['false', 'yml']) {|t|
      t.binmode
      t.write("--- !ruby/range\nbegin: 0\nend: 42\nexcl: false\n")
      t.close
      assert_equal 0..42, Psych.safe_load_file(t.path, permitted_classes: [Range])
      assert_raise(Psych::DisallowedClass) {
        Psych.safe_load_file(t.path)
      }
    }
  end

  def test_parse_file
    Tempfile.create(['yikes', 'yml']) {|t|
      t.binmode
      t.write('--- hello world')
      t.close
      assert_equal 'hello world', Psych.parse_file(t.path).transform
    }
  end

  def test_parse_file_default_fallback
    Tempfile.create(['empty', 'yml']) do |t|
      assert_equal false, Psych.parse_file(t.path)
    end
  end

  def test_degenerate_strings
    assert_equal false, Psych.unsafe_load('    ')
    assert_equal false, Psych.parse('   ')
    assert_equal false, Psych.unsafe_load('')
    assert_equal false, Psych.parse('')
  end

  def test_callbacks
    types = []
    appender = lambda { |*args| types << args }

    Psych.add_domain_type('example.com:2002', 'foo', &appender)
    Psych.load <<-eoyml
- !tag:example.com:2002:foo bar
    eoyml

    assert_equal [
      ["tag:example.com:2002:foo", "bar"]
    ], types
  end

  def test_symbolize_names
    yaml = <<-eoyml
foo:
  bar: baz
  1: 2
hoge:
  - fuga: piyo
    eoyml

    result = Psych.load(yaml)
    assert_equal result, { "foo" => { "bar" => "baz", 1 => 2 }, "hoge" => [{ "fuga" => "piyo" }] }

    result = Psych.load(yaml, symbolize_names: true)
    assert_equal result, { foo: { bar: "baz", 1 => 2 }, hoge: [{ fuga: "piyo" }] }

    result = Psych.safe_load(yaml, symbolize_names: true)
    assert_equal result, { foo: { bar: "baz", 1 => 2 }, hoge: [{ fuga: "piyo" }] }
  end

  def test_safe_dump_defaults
    yaml = <<-eoyml
---
array:
- 1
float: 13.12
booleans:
- true
- false
eoyml

    payload = Psych.safe_dump({
      "array" => [1],
      "float" => 13.12,
      "booleans" => [true, false],
    })
    assert_equal yaml, payload
  end

  def test_safe_dump_unpermitted_class
    error = assert_raise Psych::DisallowedClass do
      Psych.safe_dump(Object.new)
    end
    assert_equal "Tried to dump unspecified class: Object", error.message

    hash_subclass = Class.new(Hash)
    error = assert_raise Psych::DisallowedClass do
      Psych.safe_dump(hash_subclass.new)
    end
    assert_equal "Tried to dump unspecified class: #{hash_subclass.inspect}", error.message
  end

  def test_safe_dump_extra_permitted_classes
    assert_equal "--- !ruby/object {}\n", Psych.safe_dump(Object.new, permitted_classes: [Object])
  end

  def test_safe_dump_symbols
    assert_equal Psych.dump(:foo), Psych.safe_dump(:foo, permitted_classes: [Symbol])
    assert_equal Psych.dump(:foo), Psych.safe_dump(:foo, permitted_symbols: [:foo])

    error = assert_raise Psych::DisallowedClass do
      Psych.safe_dump(:foo)
    end
    assert_equal "Tried to dump unspecified class: Symbol(:foo)", error.message

    assert_match(/\A--- :foo\n(?:\.\.\.\n)?\z/, Psych.safe_dump(:foo, permitted_symbols: [:foo]))
  end

  def test_safe_dump_stringify_names
    yaml = <<-eoyml
---
foo:
  bar: bar
  'no': special escapes
  123: number
eoyml

    payload = Psych.safe_dump({
      foo: {
        bar: "bar",
        no: "special escapes",
        123 => "number"
      }
    }, stringify_names: true)
    assert_equal yaml, payload

    assert_equal("---\nfoo: :bar\n", Psych.safe_dump({foo: :bar}, stringify_names: true, permitted_symbols: [:bar]))

    error = assert_raise Psych::DisallowedClass do
      Psych.safe_dump({foo: :bar}, stringify_names: true)
    end
    assert_equal "Tried to dump unspecified class: Symbol(:bar)", error.message
  end

  def test_safe_dump_aliases
    x = []
    x << x
    error = assert_raise Psych::BadAlias do
      Psych.safe_dump(x)
    end
    assert_equal "Tried to dump an aliased object", error.message

    assert_equal "--- &1\n" + "- *1\n", Psych.safe_dump(x, aliases: true)
  end

end
