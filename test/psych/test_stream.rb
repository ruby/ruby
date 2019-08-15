# frozen_string_literal: true
require_relative 'helper'

module Psych
  class TestStream < TestCase
    [
      [Psych::Nodes::Alias, :alias?],
      [Psych::Nodes::Document, :document?],
      [Psych::Nodes::Mapping, :mapping?],
      [Psych::Nodes::Scalar, :scalar?],
      [Psych::Nodes::Sequence, :sequence?],
      [Psych::Nodes::Stream, :stream?],
    ].each do |klass, block|
      define_method :"test_predicate_#{block}" do
        rb = Psych.parse_stream("---\n- foo: bar\n- &a !!str Anchored\n- *a")
        nodes = rb.grep(klass)
        assert_operator nodes.length, :>, 0
        assert_equal nodes, rb.find_all(&block)
      end
    end

    def test_parse_partial
      rb = Psych.parse("--- foo\n...\n--- `").to_ruby
      assert_equal 'foo', rb
    end

    def test_load_partial
      rb = Psych.load("--- foo\n...\n--- `")
      assert_equal 'foo', rb
    end

    def test_parse_stream_yields_documents
      list = []
      Psych.parse_stream("--- foo\n...\n--- bar") do |doc|
        list << doc.to_ruby
      end
      assert_equal %w{ foo bar }, list
    end

    def test_parse_stream_break
      list = []
      Psych.parse_stream("--- foo\n...\n--- `") do |doc|
        list << doc.to_ruby
        break
      end
      assert_equal %w{ foo }, list
    end

    def test_load_stream_yields_documents
      list = []
      Psych.load_stream("--- foo\n...\n--- bar") do |ruby|
        list << ruby
      end
      assert_equal %w{ foo bar }, list
    end

    def test_load_stream_break
      list = []
      Psych.load_stream("--- foo\n...\n--- `") do |ruby|
        list << ruby
        break
      end
      assert_equal %w{ foo }, list
    end

    def test_explicit_documents
      io     = StringIO.new
      stream = Psych::Stream.new(io)
      stream.start
      stream.push({ 'foo' => 'bar' })

      assert !stream.finished?, 'stream not finished'
      stream.finish
      assert stream.finished?, 'stream finished'

      assert_match(/^---/, io.string)
      assert_match(/\.\.\.$/, io.string)
    end

    def test_start_takes_block
      io     = StringIO.new
      stream = Psych::Stream.new(io)
      stream.start do |emitter|
        emitter.push({ 'foo' => 'bar' })
      end

      assert stream.finished?, 'stream finished'
      assert_match(/^---/, io.string)
      assert_match(/\.\.\.$/, io.string)
    end

    def test_no_backreferences
      io     = StringIO.new
      stream = Psych::Stream.new(io)
      stream.start do |emitter|
        x = { 'foo' => 'bar' }
        emitter.push x
        emitter.push x
      end

      assert stream.finished?, 'stream finished'
      assert_match(/^---/, io.string)
      assert_match(/\.\.\.$/, io.string)
      assert_equal 2, io.string.scan('---').length
      assert_equal 2, io.string.scan('...').length
      assert_equal 2, io.string.scan('foo').length
      assert_equal 2, io.string.scan('bar').length
    end
  end
end
