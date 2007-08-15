# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/testresult'

module RUNIT
  class TestResult < Test::Unit::TestResult
    attr_reader(:errors, :failures)
    def succeed?
      return passed?
    end
    def failure_size
      return failure_count
    end
    def run_asserts
      return assertion_count
    end
    def error_size
      return error_count
    end
    def run_tests
      return run_count
    end
    def add_failure(failure)
      def failure.at
        return location
      end
      def failure.err
        return message
      end
      super(failure)
    end
    def add_error(error)
      def error.at
        return location
      end
      def error.err
        return exception
      end
      super(error)
    end
  end
end
