# :nodoc:
#
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

module Test
  module Unit

    # Encapsulates an error in a test. Created by
    # Test::Unit::TestCase when it rescues an exception thrown
    # during the processing of a test.
    class Error
      attr_reader(:location, :exception)

      SINGLE_CHARACTER = 'E'

      # Creates a new Error with the given location and
      # exception.
      def initialize(location, exception)
        @location = location
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
        "#{@location}:\n#{message}"
      end

      # Returns a verbose version of the error description.
      def long_display
        backtrace = self.class.filter(@exception.backtrace).join("\n    ")
        "Error!!!\n#{short_display}\n    #{backtrace}"
      end

      # Overridden to return long_display.
      def to_s
        long_display
      end

      SEPARATOR_PATTERN = '[\\\/:]'
      def self.filter(backtrace) # :nodoc:
        @test_unit_patterns ||= $:.collect {
          | path |
          /^#{Regexp.escape(path)}#{SEPARATOR_PATTERN}test#{SEPARATOR_PATTERN}unit#{SEPARATOR_PATTERN}/
        }.push(/#{SEPARATOR_PATTERN}test#{SEPARATOR_PATTERN}unit\.rb/)

        return backtrace.delete_if {
            | line |
            @test_unit_patterns.detect {
              | pattern |
              line =~ pattern
            }
          }
      end
    end
  end
end
