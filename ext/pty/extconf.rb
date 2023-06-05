# frozen_string_literal: true
require 'mkmf'

$INCFLAGS << " -I$(topdir) -I$(top_srcdir)"

if /mswin|mingw|bccwin/ !~ RUBY_PLATFORM
  have_header("sys/stropts.h")
  have_func("setresuid")
  have_header("libutil.h")
  have_header("pty.h")
  have_header("pwd.h")
  if /openbsd/ =~ RUBY_PLATFORM
    have_header("util.h") # OpenBSD openpty
    util = have_library("util", "openpty")
  end
  if have_func("posix_openpt") or
      (util or have_func("openpty")) or
      have_func("_getpty") or
      have_func("ptsname") or
      have_func("ioctl")
    create_makefile('pty')
  end
end
