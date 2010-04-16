#--
#
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2003 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/assertions'
require 'test/unit/failure'
require 'test/unit/error'
require 'test/unit/testsuite'
require 'test/unit/assertionfailederror'
require 'test/unit/util/backtracefilter'

module Test
  module Unit

    # Ties everything together. If you subclass and add your own
    # test methods, it takes care of making them into tests and
    # wrapping those tests into a suite. It also does the
    # nitty-gritty of actually running an individual test and
    # collecting its results into a Test::Unit::TestResult object.
    class TestCase
      include Assertions
      include Util::BacktraceFilter

      attr_reader :method_name

      STARTED = name + "::STARTED"
      FINISHED = name + "::FINISHED"

      ##
      # These exceptions are not caught by #run.

      PASSTHROUGH_EXCEPTIONS = [NoMemoryError, SignalException, Interrupt,
                                SystemExit]

      # Creates a new instance of the fixture for running the
      # test represented by test_method_name.
      def initialize(test_method_name)
        unless(respond_to?(test_method_name) and
               (method(test_method_name).arity == 0 ||
                method(test_method_name).arity == -1))
          throw :invalid_test
        end
        @method_name = test_method_name
        @test_passed = true
      end

      # Rolls up all of the test* methods in the fixture into
      # one suite, creating a new instance of the fixture for
      # each method.
      def self.suite
        method_names = public_instance_methods(true)
        tests = method_names.delete_if {|method_name| method_name !~ /^test./}
        suite = TestSuite.new(name)
        tests.sort.each do
          |test|
          catch(:invalid_test) do
            suite << new(test)
          end
        end
        if (suite.empty?)
          catch(:invalid_test) do
            suite << new("default_test")
          end
        end
        return suite
      end

      # Runs the individual test method represented by this
      # instance of the fixture, collecting statistics, failures
      # and errors in result.
      def run(result)
        yield(STARTED, name)
        @_result = result
        begin
          setup
          __send__(@method_name)
        rescue AssertionFailedError => e
          add_failure(e.message, e.backtrace)
        rescue Exception
          raise if PASSTHROUGH_EXCEPTIONS.include? $!.class
          add_error($!)
        ensure
          begin
            teardown
          rescue AssertionFailedError => e
            add_failure(e.message, e.backtrace)
          rescue Exception
            raise if PASSTHROUGH_EXCEPTIONS.include? $!.class
            add_error($!)
          end
        end
        result.add_run
        yield(FINISHED, name)
      end

      # Called before every test method runs. Can be used
      # to set up fixture information.
      def setup
      end

      # Called after every test method runs. Can be used to tear
      # down fixture information.
      def teardown
      end

      def default_test
        flunk("No tests were specified")
      end

      # Returns whether this individual test passed or
      # not. Primarily for use in teardown so that artifacts
      # can be left behind if the test fails.
      def passed?
        return @test_passed
      end
      private :passed?

      def size
        1
      end

      def add_assertion
        @_result.add_assertion
      end
      private :add_assertion

      def add_failure(message, all_locations=caller())
        @test_passed = false
        @_result.add_failure(Failure.new(name, filter_backtrace(all_locations), message))
      end
      private :add_failure

      def add_error(exception)
        @test_passed = false
        @_result.add_error(Error.new(name, exception))
      end
      private :add_error

      # Returns a human-readable name for the specific test that
      # this instance of TestCase represents.
      def name
        "#{@method_name}(#{self.class.name})"
      end

      # Overridden to return #name.
      def to_s
        name
      end

      # It's handy to be able to compare TestCase instances.
      def ==(other)
        return false unless(other.kind_of?(self.class))
        return false unless(@method_name == other.method_name)
        self.class == other.class
      end
    end
  end
end
