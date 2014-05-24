# encoding: utf-8

require "minitest/parallel_each"

# :stopdoc:
class Minitest::Unit::TestCase
  class << self
    alias :old_test_order :test_order

    def test_order
      :parallel
    end
  end
end
# :startdoc:
