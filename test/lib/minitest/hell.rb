# encoding: utf-8
######################################################################
# This file is imported from the minitest project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis.
######################################################################

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
