# frozen_string_literal: true
require 'test/unit'
require 'fiddle'

# FIXME: this is stolen from DL and needs to be refactored.

libc_so = libm_so = nil

case RUBY_PLATFORM
when /cygwin/
  libc_so = "cygwin1.dll"
  libm_so = "cygwin1.dll"
when /android/
  libdir = '/system/lib'
  if [0].pack('L!').size == 8
    libdir = '/system/lib64'
  end
  libc_so = File.join(libdir, "libc.so")
  libm_so = File.join(libdir, "libm.so")
when /linux-musl/
  Dir.glob('/lib/ld-musl-*.so.1') do |ld|
    libc_so = libm_so = ld
  end
when /linux/
  libdir = '/lib'
  case RbConfig::SIZEOF['void*']
  when 4
    # 32-bit ruby
    case RUBY_PLATFORM
    when /armv\w+-linux/
      # In the ARM 32-bit libc package such as libc6:armhf libc6:armel,
      # libc.so and libm.so are installed to /lib/arm-linux-gnu*.
      # It's not installed to /lib32.
      dir, = Dir.glob('/lib/arm-linux-gnu*')
      libdir = dir if dir && File.directory?(dir)
    else
      libdir = '/lib32' if File.directory? '/lib32'
    end
  when 8
    # 64-bit ruby
    libdir = '/lib64' if File.directory? '/lib64'
  end

  # Handle musl libc
  libc_so, = Dir.glob(File.join(libdir, "libc.musl*.so*"))
  if libc_so
    libm_so = libc_so
  else
    # glibc
    libc_so = File.join(libdir, "libc.so.6")
    libm_so = File.join(libdir, "libm.so.6")
  end
when /mingw/, /mswin/
  require "rbconfig"
  crtname = RbConfig::CONFIG["RUBY_SO_NAME"][/msvc\w+/] || 'ucrtbase'
  libc_so = libm_so = "#{crtname}.dll"
when /darwin/
  libc_so = libm_so = "/usr/lib/libSystem.B.dylib"
when /kfreebsd/
  libc_so = "/lib/libc.so.0.1"
  libm_so = "/lib/libm.so.1"
when /gnu/	#GNU/Hurd
  libc_so = "/lib/libc.so.0.3"
  libm_so = "/lib/libm.so.6"
when /mirbsd/
  libc_so = "/usr/lib/libc.so.41.10"
  libm_so = "/usr/lib/libm.so.7.0"
when /freebsd/
  libc_so = "/lib/libc.so.7"
  libm_so = "/lib/libm.so.5"
when /bsd|dragonfly/
  libc_so = "/usr/lib/libc.so"
  libm_so = "/usr/lib/libm.so"
when /solaris/
  libdir = '/lib'
  case RbConfig::SIZEOF['void*']
  when 4
    # 32-bit ruby
    libdir = '/lib' if File.directory? '/lib'
  when 8
    # 64-bit ruby
    libdir = '/lib/64' if File.directory? '/lib/64'
  end
  libc_so = File.join(libdir, "libc.so")
  libm_so = File.join(libdir, "libm.so")
when /aix/
  pwd=Dir.pwd
  libc_so = libm_so = "#{pwd}/libaixdltest.so"
  unless File.exist? libc_so
    cobjs=%w!strcpy.o!
    mobjs=%w!floats.o sin.o!
    funcs=%w!sin sinf strcpy strncpy!
    expfile='dltest.exp'
    require 'tmpdir'
    Dir.mktmpdir do |dir|
      begin
        Dir.chdir dir
        %x!/usr/bin/ar x /usr/lib/libc.a #{cobjs.join(' ')}!
        %x!/usr/bin/ar x /usr/lib/libm.a #{mobjs.join(' ')}!
        %x!echo "#{funcs.join("\n")}\n" > #{expfile}!
        require 'rbconfig'
        if RbConfig::CONFIG["GCC"] = 'yes'
          lflag='-Wl,'
        else
          lflag=''
        end
        flags="#{lflag}-bE:#{expfile} #{lflag}-bnoentry -lm"
        %x!#{RbConfig::CONFIG["LDSHARED"]} -o #{libc_so} #{(cobjs+mobjs).join(' ')} #{flags}!
      ensure
        Dir.chdir pwd
      end
    end
  end
else
  libc_so = ARGV[0] if ARGV[0] && ARGV[0][0] == ?/
  libm_so = ARGV[1] if ARGV[1] && ARGV[1][0] == ?/
  if( !(libc_so && libm_so) )
    $stderr.puts("libc and libm not found: #{$0} <libc> <libm>")
  end
end

libc_so = nil if !libc_so || (libc_so[0] == ?/ && !File.file?(libc_so))
libm_so = nil if !libm_so || (libm_so[0] == ?/ && !File.file?(libm_so))

# macOS 11.0+ removed libSystem.B.dylib from /usr/lib. But It works with dlopen.
if RUBY_PLATFORM =~ /darwin/
  libc_so = libm_so = "/usr/lib/libSystem.B.dylib"
end

if !libc_so || !libm_so
  ruby = EnvUtil.rubybin
  # When the ruby binary is 32-bit and the host is 64-bit,
  # `ldd ruby` outputs "not a dynamic executable" message.
  # libc_so and libm_so are not set.
  ldd = `ldd #{ruby}`
  #puts ldd
  libc_so = $& if !libc_so && %r{/\S*/libc\.so\S*} =~ ldd
  libm_so = $& if !libm_so && %r{/\S*/libm\.so\S*} =~ ldd
  #p [libc_so, libm_so]
end

Fiddle::LIBC_SO = libc_so
Fiddle::LIBM_SO = libm_so

module Fiddle
  class TestCase < Test::Unit::TestCase
    def setup
      @libc = Fiddle.dlopen(LIBC_SO)
      @libm = Fiddle.dlopen(LIBM_SO)
    end

    def teardown
      if /linux/ =~ RUBY_PLATFORM
        GC.start
      end
    end
  end
end
