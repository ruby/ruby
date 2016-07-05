# frozen_string_literal: false
require 'test_helper'

class TestJSONExtParser < Test::Unit::TestCase
  if defined?(JSON::Ext::Parser)
    def test_allocate
      parser = JSON::Ext::Parser.new("{}")
      assert_raise(TypeError, '[ruby-core:35079]') do
        parser.__send__(:initialize, "{}")
      end
      parser = JSON::Ext::Parser.allocate
      assert_raise(TypeError, '[ruby-core:35079]') { parser.source }
    end
  end

  if EnvUtil.gc_stress_to_class?
    def assert_no_memory_leak(code, *rest, **opt)
      code = "8.times {20_000.times {begin #{code}; rescue NoMemoryError; end}; GC.start}"
      super(["-rjson/ext/parser"],
            "GC.add_stress_to_class(JSON::Ext::Parser); "\
            "#{code}", code, *rest, rss: true, limit: 1.1, **opt)
    end

    def test_no_memory_leak_allocate
      assert_no_memory_leak("JSON::Ext::Parser.allocate")
    end
  end
end
