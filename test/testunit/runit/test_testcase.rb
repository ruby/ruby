# Author:: Masaki Suketa.
# Adapted by:: Nathaniel Talbott.
# Copyright:: Copyright (c) Masaki Suketa. All rights reserved.
# Copyright:: Copyright (c) 2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'rubyunit'

module RUNIT
  class DummyError < StandardError
  end

  class TestTestCase < RUNIT::TestCase
    def setup
      @dummy_testcase = Class.new(RUNIT::TestCase) do
        def self.name
          "DummyTestCase"
        end
        
        attr_reader :status, :dummy_called, :dummy2_called

        def initialize(*arg)
          super(*arg)
          @status = 0
          @dummy_called = false
          @dummy2_called = false
        end

        def setup
          @status = 1 if @status == 0
        end

        def test_dummy
          @status = 2 if @status == 1
          @dummy_called = true
        end

        def test_dummy2
          @status = 2 if @status == 1
          @dummy2_called = true
          raise DummyError
        end

        def teardown
          @status = 3 if @status == 2
        end
      end

      @test1 = @dummy_testcase.new('test_dummy')
      @test2 = @dummy_testcase.new('test_dummy2', 'TestCase')
    end

    def test_name
      assert_equal('DummyTestCase#test_dummy', @test1.name) # The second parameter to #initialize is ignored in emulation
      assert_equal('DummyTestCase#test_dummy2', @test2.name)
    end

    def test_run
      result = RUNIT::TestResult.new
      @test1.run(result)
      assert_equal(1, result.run_count)
    end

    def test_s_suite
      suite = @dummy_testcase.suite
      assert_instance_of(RUNIT::TestSuite, suite)
      assert_equal(2, suite.count_test_cases)
    end

    def test_teardown_err
      suite = Class.new(RUNIT::TestCase) do
        def test_foo
          assert(false)
        end
        
        def test_bar
          assert(true)
        end
        
        def teardown
          raise StandardError
        end
      end.suite

      result = RUNIT::TestResult.new
      suite.run(result)
      assert_equal(2, result.error_size)
      assert_equal(1, result.failure_size)
    end
  end
end
