# frozen_string_literal: false
if /mswin|mingw/ =~ RUBY_PLATFORM
  require '-test-/win32/console'
  require 'test/unit'

  class Test_Win32Console < Test::Unit::TestCase
    REVERSE_VIDEO = Bug::Win32::REVERSE_VIDEO

    def test_win32_console_input
      io = STDIN.tty? ? STDIN : File.open("CONIN$", "r+")
      str = "あ€"
      Bug::Win32.write_console_input(io, "#{str}\r".codepoints)
      assert_not_nil(IO.select([io], [], [], 1))
      result = io.gets
      assert_equal("#{str}\n", result);
      io.close if io != STDIN
    end
  end
end
