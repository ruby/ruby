require 'test/unit'
require 'dl'

case RUBY_PLATFORM
when /cygwin/
  LIBC_SO = "cygwin1.dll"
  LIBM_SO = "cygwin1.dll"
when /x86_64-linux/
  LIBC_SO = "/lib64/libc.so.6"
  LIBM_SO = "/lib64/libm.so.6"
when /linux/
  LIBC_SO = "/lib/libc.so.6"
  LIBM_SO = "/lib/libm.so.6"
when /mingw/, /mswin32/
  LIBC_SO = "msvcrt.dll"
  LIBM_SO = "msvcrt.dll"
else
  LIBC_SO = ARGV[0]
  LIBM_SO = ARGV[1]
  if( !(LIBC_SO && LIBM_SO) )
    $stderr.puts("#{$0} <libc> <libm>")
    exit
  end
end

module DL
  class TestBase < Test::Unit::TestCase
    include Math
    include DL

    def setup
      @libc = dlopen(LIBC_SO)
      @libm = dlopen(LIBM_SO)
    end
    
    def assert_match(expected, actual, message="")
      assert(expected === actual, message)
    end

    def assert_positive(actual)
      assert(actual > 0)
    end

    def assert_zero(actual)
      assert(actual == 0)
    end

    def assert_negative(actual)
      assert(actual < 0)
    end

    def test_empty()
    end
  end
end
