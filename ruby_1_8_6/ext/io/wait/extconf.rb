require 'mkmf'
target = "io/wait"

unless macro_defined?("DOSISH", "#include <ruby.h>")
  fionread = %w[sys/ioctl.h sys/filio.h].find do |h|
    have_macro("FIONREAD", h)
  end
  if fionread
    $defs << "-DFIONREAD_HEADER=\"<#{fionread}>\""
    create_makefile(target)
  end
else
  if have_func("rb_w32_ioctlsocket", "ruby.h")
    have_func("rb_w32_is_socket", "ruby.h")
    create_makefile(target)
  end
end
