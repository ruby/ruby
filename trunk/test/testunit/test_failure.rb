# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2003 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit'
require 'test/unit/failure'

module Test::Unit
  class TestFailure < TestCase
    def test_display
      f = Failure.new("name", [%q{location:1 in 'l'}], "message1\nmessage2")
      assert_equal("name: message1", f.short_display)
      assert_equal(<<EOM.strip, f.long_display)
Failure:
name [location:1]:
message1
message2
EOM

      f = Failure.new("name", [%q{location1:2 in 'l1'}, 'location2:1', %q{location3:3 in 'l3'}], "message1\nmessage2")
      assert_equal("name: message1", f.short_display)
      assert_equal(<<EOM.strip, f.long_display)
Failure:
name
    [location1:2 in 'l1'
     location2:1
     location3:3 in 'l3']:
message1
message2
EOM
    end
  end
end
