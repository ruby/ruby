# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/testcase'
require 'test/unit/testresult'

module Test
  module Unit
    class TC_TestResult < TestCase
      def setup
        @my_result = TestResult.new
        @my_result.add_assertion()
        @my_result.add_failure("")
        @my_result.add_error("")
      end
      def test_result_changed_notification
        called1 = false
        @my_result.add_listener( TestResult::CHANGED) {
          |result|
          assert_block("The result should be correct") { result == @my_result }
          called1 = true
        }
        @my_result.add_assertion
        assert_block("Should have been notified when the assertion happened") { called1 }
        
        called1, called2 = false, false
        @my_result.add_listener( TestResult::CHANGED) {
          |result|
          assert_block("The result should be correct") { result == @my_result }
          called2 = true
        }
        @my_result.add_assertion
        assert_block("Both listeners should have been notified for a success") { called1 && called2 }
  
        called1, called2 = false, false
        @my_result.add_failure("")
        assert_block("Both listeners should have been notified for a failure") { called1 && called2 }
  
        called1, called2 = false, false    
        @my_result.add_error("")
        assert_block("Both listeners should have been notified for an error") { called1 && called2 }
  
        called1, called2 = false, false    
        @my_result.add_run
        assert_block("Both listeners should have been notified for a run") { called1 && called2 }
      end
      def test_fault_notification
        called1 = false
        fault = "fault"
        @my_result.add_listener(TestResult::FAULT) {
          | passed_fault |
          assert_block("The fault should be correct") { passed_fault == fault }
          called1 = true
        }
  
        @my_result.add_assertion
        assert_block("Should not have been notified when the assertion happened") { !called1 }
        
        @my_result.add_failure(fault)
        assert_block("Should have been notified when the failure happened") { called1 }
        
        called1, called2 = false, false
        @my_result.add_listener(TestResult::FAULT) {
          | passed_fault |
          assert_block("The fault should be correct") { passed_fault == fault }
          called2 = true
        }
  
        @my_result.add_assertion
        assert_block("Neither listener should have been notified for a success") { !(called1 || called2) }
  
        called1, called2 = false, false
        @my_result.add_failure(fault)
        assert_block("Both listeners should have been notified for a failure") { called1 && called2 }
  
        called1, called2 = false, false    
        @my_result.add_error(fault)
        assert_block("Both listeners should have been notified for an error") { called1 && called2 }
  
        called1, called2 = false, false
        @my_result.add_run
        assert_block("Neither listener should have been notified for a run") { !(called1 || called2) }
      end
      def test_passed?
        result = TestResult.new
        assert(result.passed?, "An empty result should have passed")
  
        result.add_assertion
        assert(result.passed?, "Adding an assertion should not cause the result to not pass")
  
        result.add_run
        assert(result.passed?, "Adding a run should not cause the result to not pass")
  
        result.add_failure("")
        assert(!result.passed?, "Adding a failed assertion should cause the result to not pass")
  
        result = TestResult.new
        result.add_error("")
        assert(!result.passed?, "Adding an error should cause the result to not pass")
      end
    end
  end
end
