require 'mkmf'

have_header("sys/stropts.h")
have_func("setresuid")
if have_func("openpty") or
    have_func("_getpty") or
    have_func("ioctl")
  create_makefile('pty')
end
