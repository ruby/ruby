# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/util/observable'

module Test
  module Unit

    # Collects Test::Unit::Failure and Test::Unit::Error so that
    # they can be displayed to the user. To this end, observers
    # can be added to it, allowing the dynamic updating of, say, a
    # UI.
    class TestResult
      include Util::Observable

      CHANGED = "CHANGED"
      FAULT = "FAULT"

      attr_reader(:run_count, :assertion_count)

      # Constructs a new, empty TestResult.
      def initialize
        @run_count, @assertion_count = 0, 0
        @failures, @errors = Array.new, Array.new
      end

      # Records a test run.
      def add_run
        @run_count += 1
        notify_listeners(CHANGED, self)
      end

      # Records a Test::Unit::Failure.
      def add_failure(failure)
        @failures << failure
        notify_listeners(FAULT, failure)
        notify_listeners(CHANGED, self)
      end

      # Records a Test::Unit::Error.
      def add_error(error)
        @errors << error
        notify_listeners(FAULT, error)
        notify_listeners(CHANGED, self)
      end

      # Records an individual assertion.
      def add_assertion
        @assertion_count += 1
        notify_listeners(CHANGED, self)
      end

      # Returns a string contain the recorded runs, assertions,
      # failures and errors in this TestResult.
      def to_s
        "#{run_count} tests, #{assertion_count} assertions, #{failure_count} failures, #{error_count} errors"
      end

      # Returns whether or not this TestResult represents
      # successful completion.
      def passed?
        return @failures.empty? && @errors.empty?
      end

      # Returns the number of failures this TestResult has
      # recorded.
      def failure_count
        return @failures.size
      end

      # Returns the number of errors this TestResult has
      # recorded.
      def error_count
        return @errors.size
      end
    end
  end
end
