#--
#
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2003 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

module Test
  module Unit

    # A collection of tests which can be #run.
    #
    # Note: It is easy to confuse a TestSuite instance with
    # something that has a static suite method; I know because _I_
    # have trouble keeping them straight. Think of something that
    # has a suite method as simply providing a way to get a
    # meaningful TestSuite instance.
    class TestSuite
      attr_reader :name, :tests

      STARTED = name + "::STARTED"
      FINISHED = name + "::FINISHED"

      # Creates a new TestSuite with the given name.
      def initialize(name="Unnamed TestSuite")
        @name = name
        @tests = []
      end

      # Runs the tests and/or suites contained in this
      # TestSuite.
      def run(result, &progress_block)
        yield(STARTED, name)
        @tests.each do |test|
          test.run(result, &progress_block)
        end
        yield(FINISHED, name)
      end

      # Adds the test to the suite.
      def <<(test)
        @tests << test
        self
      end

      def delete(test)
        @tests.delete(test)
      end

      # Retuns the rolled up number of tests in this suite;
      # i.e. if the suite contains other suites, it counts the
      # tests within those suites, not the suites themselves.
      def size
        total_size = 0
        @tests.each { |test| total_size += test.size }
        total_size
      end

      def empty?
        tests.empty?
      end

      # Overridden to return the name given the suite at
      # creation.
      def to_s
        @name
      end

      # It's handy to be able to compare TestSuite instances.
      def ==(other)
        return false unless(other.kind_of?(self.class))
        return false unless(@name == other.name)
        @tests == other.tests
      end
    end
  end
end
