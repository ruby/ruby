require 'test/unit'
require 'dl'
require_relative '../ruby/envutil'

libc_so = libm_so = nil

case RUBY_PLATFORM
when /cygwin/
  libc_so = "cygwin1.dll"
  libm_so = "cygwin1.dll"
when /x86_64-linux/
  libc_so = "/lib64/libc.so.6"
  libm_so = "/lib64/libm.so.6"
when /linux/
  libdir = '/lib'
  case [0].pack('L!').size
  when 4
    # 32-bit ruby
    libdir = '/lib32' if File.directory? '/lib32'
  when 8
    # 64-bit ruby
    libdir = '/lib64' if File.directory? '/lib64'
  end
  libc_so = File.join(libdir, "libc.so.6")
  libm_so = File.join(libdir, "libm.so.6")
when /mingw/, /mswin/
  require "rbconfig"
  libc_so = libm_so = RbConfig::CONFIG["RUBY_SO_NAME"].split(/-/, 2)[0] + ".dll"
when /darwin/
  libc_so = "/usr/lib/libc.dylib"
  libm_so = "/usr/lib/libm.dylib"
when /kfreebsd/
  libc_so = "/lib/libc.so.0.1"
  libm_so = "/lib/libm.so.1"
when /bsd|dragonfly/
  libc_so = "/usr/lib/libc.so"
  libm_so = "/usr/lib/libm.so"
else
  libc_so = ARGV[0] if ARGV[0] && ARGV[0][0] == ?/
  libm_so = ARGV[1] if ARGV[1] && ARGV[1][0] == ?/
  if( !(libc_so && libm_so) )
    $stderr.puts("libc and libm not found: #{$0} <libc> <libm>")
  end
end

libc_so = nil if !libc_so || (libc_so[0] == ?/ && !File.file?(libc_so))
libm_so = nil if !libm_so || (libm_so[0] == ?/ && !File.file?(libm_so))

if !libc_so || !libm_so
  ruby = EnvUtil.rubybin
  ldd = `ldd #{ruby}`
  #puts ldd
  libc_so = $& if !libc_so && %r{/\S*/libc\.so\S*} =~ ldd
  libm_so = $& if !libm_so && %r{/\S*/libm\.so\S*} =~ ldd
  #p [libc_so, libm_so]
end

DL::LIBC_SO = libc_so
DL::LIBM_SO = libm_so

module DL
  class TestBase < Test::Unit::TestCase
    include Math
    include DL

    def setup
      @libc = dlopen(LIBC_SO)
      @libm = dlopen(LIBM_SO)
    end

    def assert_match(expected, actual, message="")
      assert_operator(expected, :===, actual, message)
    end

    def assert_positive(actual)
      assert_operator(actual, :>, 0)
    end

    def assert_zero(actual)
      assert_equal(0, actual)
    end

    def assert_negative(actual)
      assert_operator(actual, :<, 0)
    end

    def test_empty()
    end
  end
end
