# Author:: Masaki Suketa.
# Adapted by:: Nathaniel Talbott.
# Copyright:: Copyright (c) Masaki Suketa. All rights reserved.
# Copyright:: Copyright (c) 2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'rubyunit'

module RUNIT
  class TestTestSuite < RUNIT::TestCase
    def setup
      @testsuite = RUNIT::TestSuite.new
      @dummy_test = Class.new(RUNIT::TestCase) do
        def test_foo
        end
        def test_bar
        end
      end
      @dummy_empty_test = Class.new(RUNIT::TestCase){}
    end

    def test_count_test_cases
      assert_equal(0, @testsuite.count_test_cases)

      @testsuite.add(@dummy_empty_test.suite)
      assert_equal(0, @testsuite.count_test_cases)

      @testsuite.add(@dummy_test.suite)
      assert_equal(2, @testsuite.count_test_cases)

      @testsuite.add(@dummy_test.suite)
      assert_equal(4, @testsuite.count_test_cases)

      dummytest_foo = @dummy_test.new('test_foo')
      @testsuite.add(dummytest_foo)
      assert_equal(5, @testsuite.count_test_cases)
    end

    def test_add
      @testsuite.add(@dummy_empty_test.suite)
      assert_equal(0, @testsuite.size)
      assert_equal(0, @testsuite.count_test_cases)

      @testsuite.add(@dummy_test.suite)
      assert_equal(2, @testsuite.size)
      assert_equal(2, @testsuite.count_test_cases)
    end
  end
end
