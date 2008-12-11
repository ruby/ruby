require 'test/unit/assertions'

module Test
  module Unit
    class TestCase < MiniTest::Unit::TestCase
      include Assertions
      def self.test_order
        :sorted
      end
    end
  end
end
