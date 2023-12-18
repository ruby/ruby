#frozen_string_literal: false
require_relative 'test_helper'

class JSONExtParserTest < Test::Unit::TestCase
  if defined?(JSON::Ext::Parser)
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

    def parse(json)
      JSON::Ext::Parser.new(json).parse
    end
  end
end
