require 'test/unit'
require_relative '../../ruby/envutil'

module Bug
  module Win32
    class TestFdSetSize < Test::Unit::TestCase
      def test_select_with_unmatched_fd_setsize
        bug6532 = '[ruby-core:44588]'
        assert_in_out_err([], <<-INPUT, %w(:ok), [], bug6532)
          require '-test-/win32/fd_setsize'
          Bug::Win32.test_select
          p :ok
        INPUT
      end

      def test_fdset_with_unmatched_fd_setsize
        bug6532 = '[ruby-core:44588]'
        assert_in_out_err([], <<-INPUT, %w(:ok), [], bug6532)
          require '-test-/win32/fd_setsize'
          p :ok if Bug::Win32.test_fdset
        INPUT
      end
    end
  end
end if /mswin|mingw/ =~ RUBY_PLATFORM
