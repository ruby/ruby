# Author:: Nathaniel Talbott.
# Copyright:: Copyright (c) 2000-2002 Nathaniel Talbott. All rights reserved.
# License:: Ruby license.

require 'test/unit/error'

module Test
  module Unit
    class TC_Error < TestCase
      def setup
        @old_load_path = $:.dup
        $:.replace(['C:\some\old\path'])
      end
      
      def test_backtrace_filtering
        backtrace = [%q{tc_thing.rb:4:in '/'}]
        
        backtrace.concat([%q{tc_thing.rb:4:in 'test_stuff'},
            %q{C:\some\old\path/test/unit/testcase.rb:44:in 'send'},
            %q{C:\some\old\path\test\unit\testcase.rb:44:in 'run'},
            %q{tc_thing.rb:3}])
        assert_equal([backtrace[0..1], backtrace[-1]].flatten, Error.filter(backtrace), "Should filter out all TestUnit-specific lines")
      end
      
      def teardown
        $:.replace(@old_load_path)
      end
    end
  end
end
