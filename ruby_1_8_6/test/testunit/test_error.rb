# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit'

module Test
  module Unit
    class TC_Error < TestCase
      TF_Exception = Struct.new('TF_Exception', :message, :backtrace)
      def test_display
        ex = TF_Exception.new("message1\nmessage2", ['line1', 'line2'])
        e = Error.new("name", ex)
        assert_equal("name: #{TF_Exception.name}: message1", e.short_display)
        assert_equal(<<EOM.strip, e.long_display)
Error:
name:
Struct::TF_Exception: message1
message2
    line1
    line2
EOM
      end
    end
  end
end
