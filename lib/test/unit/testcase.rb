require 'test/unit/assertions'

module Test
  module Unit
    # remove silly TestCase class
    remove_const(:TestCase) if defined?(self::TestCase)

    class TestCase < MiniTest::Unit::TestCase
      include Assertions
      def self.test_order
        :sorted
      end
    end
  end
end
