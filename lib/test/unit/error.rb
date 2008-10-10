#--
#
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/util/backtracefilter'

module Test
  module Unit

    # Encapsulates an error in a test. Created by
    # Test::Unit::TestCase when it rescues an exception thrown
    # during the processing of a test.
    class Error
      include Util::BacktraceFilter

      attr_reader(:test_name, :exception)

      SINGLE_CHARACTER = 'E'

      # Creates a new Error with the given test_name and
      # exception.
      def initialize(test_name, exception)
        @test_name = test_name
        @exception = exception
      end

      # Returns a single character representation of an error.
      def single_character_display
        SINGLE_CHARACTER
      end

      # Returns the message associated with the error.
      def message
        "#{@exception.class.name}: #{@exception.message}"
      end

      # Returns a brief version of the error description.
      def short_display
        "#@test_name: #{message.split("\n")[0]}"
      end

      # Returns a verbose version of the error description.
      def long_display
        backtrace = filter_backtrace(@exception.backtrace).join("\n    ")
        "Error:\n#@test_name:\n#{message}\n    #{backtrace}"
      end

      # Overridden to return long_display.
      def to_s
        long_display
      end
    end
  end
end
