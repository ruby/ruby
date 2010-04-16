# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/testsuite'

module RUNIT
  class TestSuite < Test::Unit::TestSuite
    def add_test(*args)
      add(*args)
    end

    def add(*args)
      self.<<(*args)
    end

    def count_test_cases
      return size
    end

    def run(result, &progress_block)
      progress_block = proc {} unless (block_given?)
      super(result, &progress_block)
    end
  end
end
