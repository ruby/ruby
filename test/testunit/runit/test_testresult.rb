# Author:: Masaki Suketa.
# Adapted by:: Nathaniel Talbott.
# Copyright:: Copyright (c) Masaki Suketa. All rights reserved.
# Copyright:: Copyright (c) 2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'rubyunit'

module RUNIT
  class TestTestResult < RUNIT::TestCase
    def setup
      @result = RUNIT::TestResult.new

      @normal_suite = Class::new(RUNIT::TestCase) do
        def test_1
          assert(true)
          assert(true)
        end
      end.suite

      @failure_suite = Class::new(RUNIT::TestCase) do
        def test_1
          assert(true)
          assert(false)
        end
      end.suite

      @error_suite = Class::new(RUNIT::TestCase) do
        def setup
          raise ScriptError
        end
        def test_1
          assert(true)
        end
      end.suite

      @multi_failure_suite = Class::new(RUNIT::TestCase) do
        def test1
          assert(false)
        end
        def test2
          assert(false)
        end
        def test3
          assert(false)
        end
      end.suite

      @with_error_suite = Class::new(RUNIT::TestCase) do
        def test1
          raise StandardError
        end
      end.suite

      @multi_error_suite = Class::new(RUNIT::TestCase) do
        def test1
          raise StandardError
        end
        def test2
          raise StandardError
        end
        def test3
          raise StandardError
        end
      end.suite

      @multi_suite = Class::new(RUNIT::TestCase) do
        def test_1
          assert(true)
          assert(true)
        end
        def test_2
          assert(true)
        end
        def test_3
          assert(true)
          assert(false)
          assert(true)
        end
      end.suite
    end

    def test_error_size
      @normal_suite.run(@result)
      assert_equal(0, @result.error_size)
      @with_error_suite.run(@result)
      assert_equal(1, @result.error_size)
      @multi_error_suite.run(@result)
      assert_equal(4, @result.error_size)
    end

    def test_errors
      @normal_suite.run(@result)
      assert_equal(0, @result.errors.size)
    end

    def test_failure_size
      @normal_suite.run(@result)
      assert_equal(0, @result.failure_size)
      @failure_suite.run(@result)
      assert_equal(1, @result.failure_size)
      @multi_failure_suite.run(@result)
      assert_equal(4, @result.failure_size)
    end

    def test_failures
      @normal_suite.run(@result)
      assert_equal(0, @result.failures.size)
      @failure_suite.run(@result)
      assert_equal(1, @result.failures.size)
      @multi_failure_suite.run(@result)
      assert_equal(4, @result.failures.size)
    end

    def test_run_no_exception
      assert_no_exception {
        @error_suite.run(@result)
      }
    end

    def test_run_asserts
      @normal_suite.run(@result)
      assert_equal(2, @result.run_asserts)
    end

    def test_run_asserts2
      @failure_suite.run(@result)
      assert_equal(2, @result.run_asserts)
    end

    def test_run_tests
      assert_equal(0, @result.run_tests)
      @normal_suite.run(@result)
      assert_equal(1, @result.run_tests)
      @multi_suite.run(@result)
      assert_equal(4, @result.run_tests)
    end

    def test_succeed?
      @normal_suite.run(@result)
      assert(@result.succeed?)
    end
  end
end
