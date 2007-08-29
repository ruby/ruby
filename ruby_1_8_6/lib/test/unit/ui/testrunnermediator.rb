#--
#
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit'
require 'test/unit/util/observable'
require 'test/unit/testresult'

module Test
  module Unit
    module UI

      # Provides an interface to write any given UI against,
      # hopefully making it easy to write new UIs.
      class TestRunnerMediator
        RESET = name + "::RESET"
        STARTED = name + "::STARTED"
        FINISHED = name + "::FINISHED"
        
        include Util::Observable
        
        # Creates a new TestRunnerMediator initialized to run
        # the passed suite.
        def initialize(suite)
          @suite = suite
        end

        # Runs the suite the TestRunnerMediator was created
        # with.
        def run_suite
          Unit.run = true
          begin_time = Time.now
          notify_listeners(RESET, @suite.size)
          result = create_result
          notify_listeners(STARTED, result)
          result_listener = result.add_listener(TestResult::CHANGED) do |updated_result|
            notify_listeners(TestResult::CHANGED, updated_result)
          end
          
          fault_listener = result.add_listener(TestResult::FAULT) do |fault|
            notify_listeners(TestResult::FAULT, fault)
          end
          
          @suite.run(result) do |channel, value|
            notify_listeners(channel, value)
          end
          
          result.remove_listener(TestResult::FAULT, fault_listener)
          result.remove_listener(TestResult::CHANGED, result_listener)
          end_time = Time.now
          elapsed_time = end_time - begin_time
          notify_listeners(FINISHED, elapsed_time) #"Finished in #{elapsed_time} seconds.")
          return result
        end

        private
        # A factory method to create the result the mediator
        # should run with. Can be overridden by subclasses if
        # one wants to use a different result.
        def create_result
          return TestResult.new
        end
      end
    end
  end
end
