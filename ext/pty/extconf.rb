require 'mkmf'

if /mswin32|mingw/ !~ RUBY_PLATFORM
  have_header("sys/stropts.h")
  have_func("setresuid")
  $CFLAGS << "-DHAVE_DEV_PTMX" if /cygwin/ === RUBY_PLATFORM
  if have_func("openpty") or
      have_func("_getpty") or
      have_func("ioctl")
    create_makefile('pty')
  end
end
