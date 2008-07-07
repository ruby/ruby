require 'mkmf'

if /mswin32|mingw|bccwin32/ !~ RUBY_PLATFORM
  have_header("sys/stropts.h")
  have_func("setresuid")
  have_header("libutil.h")
  have_header("pty.h")
  have_library("util", "openpty")
  if have_func("openpty") or
      have_func("_getpty") or
      have_func("ptsname") or
      have_func("ioctl")
    create_makefile('pty')
  end
end
