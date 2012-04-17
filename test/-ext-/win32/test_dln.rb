require 'test/unit'
require_relative '../../ruby/envutil'

module Bug
  module Win32
    class TestDln < Test::Unit::TestCase
      def test_check_imported
        bug = '[Bug #6303]'
        assert_in_out_err(['-r-test-/win32/dln', '-eexit'], '', [], [], bug, timeout: 10)
      end
    end
  end
end if /mswin|mingw/ =~ RUBY_PLATFORM
