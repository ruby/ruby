# frozen_string_literal: false
if /mswin|mingw/ =~ RUBY_PLATFORM and STDOUT.tty?
  require '-test-/win32/console'
  require 'io/console'
  require 'test/unit'

  class Test_Win32Console < Test::Unit::TestCase
    REVERSE_VIDEO = Bug::Win32::REVERSE_VIDEO

    def reverse_video(fore, back = 0x0)
      info = Bug::Win32.console_info(STDOUT)
      if (info.attr & REVERSE_VIDEO) == 0
        (fore << 4) | back
      else
        (back << 4) | fore | REVERSE_VIDEO
      end
    end

    def reset
      Bug::Win32.console_attribute(STDOUT, 7)
    end

    alias setup reset
    alias teardown reset

    def test_default
      info = Bug::Win32.console_info(STDOUT)
      assert_equal(7, info.attr);
    end

    def test_reverse
      print "\e[7m"
      info = Bug::Win32.console_info(STDOUT)
      assert_equal(reverse_video(0x7), info.attr);
    end

    def test_bold
      print "\e[1m"
      info = Bug::Win32.console_info(STDOUT)
      assert_equal(0x8, info.attr&0x8);
    end

    def test_bold_reverse
      print "\e[1;7m"
      info = Bug::Win32.console_info(STDOUT)
      assert_equal(reverse_video(0xf), info.attr);
    end

    def test_reverse_bold
      print "\e[7;1m"
      info = Bug::Win32.console_info(STDOUT)
      assert_equal(reverse_video(0xf), info.attr);
    end
  end
end
