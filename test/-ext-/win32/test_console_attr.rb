# frozen_string_literal: false
if /mswin|mingw/ =~ RUBY_PLATFORM and STDOUT.tty?
  require '-test-/win32/console'
  require 'io/console'
  require 'test/unit'

  class Test_Win32Console < Test::Unit::TestCase
    def reset
      STDOUT.console_attribute(7)
    end

    alias setup reset
    alias teardown reset

    def test_default
      info = STDOUT.console_info
      assert_equal(7, info.attr);
    end

    def test_reverse
      print "\e[7m"
      info = STDOUT.console_info
      assert_equal(0x70, info.attr);
    end

    def test_bold
      print "\e[1m"
      info = STDOUT.console_info
      assert_equal(0x8, info.attr&0x8);
    end

    def test_bold_reverse
      print "\e[1;7m"
      info = STDOUT.console_info
      assert_equal(0xf0, info.attr);
    end

    def test_reverse_bold
      print "\e[7;1m"
      info = STDOUT.console_info
      assert_equal(0xf0, info.attr);
    end
  end
end
