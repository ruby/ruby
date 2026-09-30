# frozen_string_literal: false
require 'test/unit'

module Bug
  module Win32
    class TestExitProcess < Test::Unit::TestCase
      def test_exit_from_foreign_thread_with_pipe
        assert_ruby_status(["-", EnvUtil.rubybin], <<-INPUT)
          require '-test-/win32/exit_process'
          IO.popen([ARGV[0], "-e", ""])
          Bug::Win32.exit_process_from_foreign_thread(0)
          sleep
        INPUT
      end
    end
  end
end if /mswin|mingw/ =~ RUBY_PLATFORM
