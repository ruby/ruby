# frozen_string_literal: true
require_relative 'test_helper'

class JSONExtParserTest < Test::Unit::TestCase
  include JSON

  def test_allocate
    parser = JSON::Ext::Parser.new("{}")
    parser.__send__(:initialize, "{}")
    assert_equal "{}", parser.source

    parser = JSON::Ext::Parser.allocate
    assert_nil parser.source
  end

  def test_error_messages
    ex = assert_raise(ParserError) { parse('Infinity something') }
    unless RUBY_PLATFORM =~ /java/
      assert_equal "unexpected token 'Infinity' at line 1 column 1", ex.message
    end

    ex = assert_raise(ParserError) { parse('foo bar') }
    unless RUBY_PLATFORM =~ /java/
      assert_equal "unexpected token 'foo' at line 1 column 1", ex.message
    end

    ex = assert_raise(ParserError) { parse('-Infinity something') }
    unless RUBY_PLATFORM =~ /java/
      assert_equal "unexpected token '-Infinity' at line 1 column 1", ex.message
    end

    ex = assert_raise(ParserError) { parse('NaN something') }
    unless RUBY_PLATFORM =~ /java/
      assert_equal "unexpected token 'NaN' at line 1 column 1", ex.message
    end

    ex = assert_raise(ParserError) { parse('   ') }
    unless RUBY_PLATFORM =~ /java/
      assert_equal "unexpected end of input at line 1 column 4", ex.message
    end

    ex = assert_raise(ParserError) { parse('{   ') }
    unless RUBY_PLATFORM =~ /java/
      assert_equal "expected object key, got EOF at line 1 column 5", ex.message
    end
  end

  if GC.respond_to?(:stress=)
    def test_gc_stress_parser_new
      payload = JSON.dump([{ foo: 1, bar: 2, baz: 3, egg: { spam: 4 } }] * 10)

      previous_stress = GC.stress
      JSON::Parser.new(payload).parse
    ensure
      GC.stress = previous_stress
    end

    def test_gc_stress
      payload = JSON.dump([{ foo: 1, bar: 2, baz: 3, egg: { spam: 4 } }] * 10)

      previous_stress = GC.stress
      JSON.parse(payload)
    ensure
      GC.stress = previous_stress
    end
  end

  def parse(json)
    JSON::Ext::Parser.new(json).parse
  end
end
