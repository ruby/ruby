# frozen_string_literal: true
require_relative 'test_helper'

class JSONExtParserTest < Test::Unit::TestCase
  include JSON

  def test_allocate
    parser = JSON::Ext::Parser.new("{}")
    assert_raise(TypeError, '[ruby-core:35079]') do
      parser.__send__(:initialize, "{}")
    end
    parser = JSON::Ext::Parser.allocate
    assert_raise(TypeError, '[ruby-core:35079]') { parser.source }
  end

  def test_error_messages
    ex = assert_raise(ParserError) { parse('Infinity') }
    assert_equal "unexpected token at 'Infinity'", ex.message

    unless RUBY_PLATFORM =~ /java/
      ex = assert_raise(ParserError) { parse('-Infinity') }
      assert_equal "unexpected token at '-Infinity'", ex.message
    end

    ex = assert_raise(ParserError) { parse('NaN') }
    assert_equal "unexpected token at 'NaN'", ex.message
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
