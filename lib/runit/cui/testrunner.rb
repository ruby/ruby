# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/ui/console/testrunner'
require 'runit/testresult'

module RUNIT
  module CUI
    class TestRunner < Test::Unit::UI::Console::TestRunner
      @@quiet_mode = false

      def self.run(suite)
        self.new().run(suite)
      end

      def initialize
        super nil
      end

      def run(suite, quiet_mode=@@quiet_mode)
        @suite = suite
        def @suite.suite
          self
        end
        @output_level = (quiet_mode ? Test::Unit::UI::PROGRESS_ONLY : Test::Unit::UI::VERBOSE)
        start
      end

      def create_mediator(suite)
        mediator = Test::Unit::UI::TestRunnerMediator.new(suite)
        class << mediator
          attr_writer :result_delegate
          def create_result
            return @result_delegate.create_result
          end
        end
        mediator.result_delegate = self
        return mediator
      end

      def create_result
        return RUNIT::TestResult.new
      end

      def self.quiet_mode=(boolean)
        @@quiet_mode = boolean
      end
    end
  end
end
