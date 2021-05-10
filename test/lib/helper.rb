require "test/unit"
require_relative "core_assertions"

Test::Unit::TestCase.include Test::Unit::CoreAssertions

module Test
  module Unit
    class TestCase
      def windows? platform = RUBY_PLATFORM
        /mswin|mingw/ =~ platform
      end
    end
  end
end
