# :nodoc:
#
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

module Test
  module Unit

    # Encapsulates a test failure. Created by Test::Unit::TestCase
    # when an assertion fails.
    class Failure
      attr_reader(:location, :message)
      
      SINGLE_CHARACTER = 'F'

      # Creates a new Failure with the given location and
      # message.
      def initialize(location, message)
        @location = location
        @message = message
      end
      
      # Returns a single character representation of a failure.
      def single_character_display
        SINGLE_CHARACTER
      end

      # Returns a brief version of the error description.
      def short_display
        "#{@location}:\n#{@message}"
      end

      # Returns a verbose version of the error description.
      def long_display
        "Failure!!!\n#{short_display}"
      end

      # Overridden to return long_display.
      def to_s
        long_display
      end
    end
  end
end
