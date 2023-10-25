# frozen_string_literal: true
begin
  require_relative 'helper'
rescue LoadError
end

class TestFiddle < Fiddle::TestCase
  def test_nil_true_etc
    assert_equal Fiddle::Qtrue, Fiddle.dlwrap(true)
    assert_equal Fiddle::Qfalse, Fiddle.dlwrap(false)
    assert_equal Fiddle::Qnil, Fiddle.dlwrap(nil)
    assert Fiddle::Qundef
  end

  def test_windows_constant
    require 'rbconfig'
    if RbConfig::CONFIG['host_os'] =~ /mswin|mingw/
      assert Fiddle::WINDOWS, "Fiddle::WINDOWS should be 'true' on Windows platforms"
    else
      refute Fiddle::WINDOWS, "Fiddle::WINDOWS should be 'false' on non-Windows platforms"
    end
  end

  def test_dlopen_linker_script_input_linux
    omit("This is only for Linux") unless RUBY_PLATFORM.match?("linux")
    if Dir.glob("/usr/lib/*/libncurses.so").empty?
      omit("libncurses.so is needed")
    end
    # libncurses.so uses INPUT() on Debian GNU/Linux
    # $ cat /usr/lib/x86_64-linux-gnu/libncurses.so
    # INPUT(libncurses.so.6 -ltinfo)
    handle = Fiddle.dlopen("libncurses.so")
    begin
      assert_equal("libncurses.so",
                   File.basename(handle.file_name, ".*"))
    ensure
      handle.close
    end
  end

  def test_dlopen_linker_script_group_linux
    omit("This is only for Linux") unless RUBY_PLATFORM.match?("linux")
    # libc.so uses GROUP() on Debian GNU/Linux
    # $ cat /usr/lib/x86_64-linux-gnu/libc.so
    # /* GNU ld script
    #    Use the shared library, but some functions are only in
    #    the static library, so try that secondarily.  */
    # OUTPUT_FORMAT(elf64-x86-64)
    # GROUP ( /lib/x86_64-linux-gnu/libc.so.6 /usr/lib/x86_64-linux-gnu/libc_nonshared.a  AS_NEEDED ( /lib64/ld-linux-x86-64.so.2 ) )
    handle = Fiddle.dlopen("libc.so")
    begin
      assert_equal("libc.so",
                   File.basename(handle.file_name, ".*"))
    ensure
      handle.close
    end
  end
end if defined?(Fiddle)
