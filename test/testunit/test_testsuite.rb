# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2003 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit'

module Test
  module Unit
    class TC_TestSuite < TestCase
      def setup
        @testcase1 = Class.new(TestCase) do
          def test_succeed1
            assert_block { true }
          end
          def test_fail
            assert_block { false }
          end
        end

        @testcase2 = Class.new(TestCase) do
          def test_succeed2
            assert_block { true }
          end
          def test_error
            raise
          end
        end
      end

      def test_add
        s = TestSuite.new
        assert_equal(s, s << self.class.new("test_add"))
      end

      def test_delete
        s = TestSuite.new
        t1 = self.class.new("test_delete")
        s << t1
        t2 = self.class.new("test_add")
        s << t2
        assert_equal(t1, s.delete(t1))
        assert_nil(s.delete(t1))
        assert_equal(TestSuite.new << t2, s)
      end

      def test_size
        suite = TestSuite.new
        suite2 = TestSuite.new
        suite2 << self.class.new("test_size")
        suite << suite2
        suite << self.class.new("test_size")
        assert_equal(2, suite.size, "The count should be correct")
      end

      def test_run
        progress = []
        suite = @testcase1.suite
        result = TestResult.new
        suite.run(result) { |*values| progress << values }

        assert_equal(2, result.run_count, "Should have had four test runs")
        assert_equal(1, result.failure_count, "Should have had one test failure")
        assert_equal(0, result.error_count, "Should have had one test error")
        assert_equal([[TestSuite::STARTED, suite.name],
                [TestCase::STARTED, "test_fail(#{suite.name})"],
                [TestCase::FINISHED, "test_fail(#{suite.name})"],
                [TestCase::STARTED, "test_succeed1(#{suite.name})"],
                [TestCase::FINISHED, "test_succeed1(#{suite.name})"],
                [TestSuite::FINISHED, suite.name]],
                progress, "Should have had the correct progress")

        suite = TestSuite.new
        suite << @testcase1.suite
        suite << @testcase2.suite
        result = TestResult.new
        progress = []
        suite.run(result) { |*values| progress << values }

        assert_equal(4, result.run_count, "Should have had four test runs")
        assert_equal(1, result.failure_count, "Should have had one test failure")
        assert_equal(1, result.error_count, "Should have had one test error")
        assert_equal(14, progress.size, "Should have had the correct number of progress calls")
      end

      def test_empty?
        assert(TestSuite.new.empty?, "A new test suite should be empty?")
        assert(!@testcase2.suite.empty?, "A test suite with tests should not be empty")
      end

      def test_equality
        suite1 = TestSuite.new
        suite2 = TestSuite.new
        assert_equal(suite1, suite2)
        assert_equal(suite2, suite1)

        suite1 = TestSuite.new('name')
        assert_not_equal(suite1, suite2)
        assert_not_equal(suite2, suite1)

        suite2 = TestSuite.new('name')
        assert_equal(suite1, suite2)
        assert_equal(suite2, suite1)

        suite1 << 'test'
        assert_not_equal(suite1, suite2)
        assert_not_equal(suite2, suite1)

        suite2 << 'test'
        assert_equal(suite1, suite2)
        assert_equal(suite2, suite1)

        suite2 = Object.new
        class << suite2
          def name
            'name'
          end
          def tests
            ['test']
          end
        end
        assert_not_equal(suite1, suite2)
        assert_not_equal(suite2, suite1)

        assert_not_equal(suite1, Object.new)
        assert_not_equal(Object.new, suite1)
      end
    end
  end
end
