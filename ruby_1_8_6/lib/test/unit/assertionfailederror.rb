#--
#
# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

module Test
  module Unit

    # Thrown by Test::Unit::Assertions when an assertion fails.
    class AssertionFailedError < StandardError
    end
  end
end
