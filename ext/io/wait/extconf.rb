require 'mkmf'
target = "io/wait"

unless macro_defined?("DOSISH", "#include <ruby.h>")
  fionread = %w[sys/ioctl.h sys/filio.h].find do |h|
    checking_for("FIONREAD") {macro_defined?("FIONREAD", "#include <#{h}>\n")}
  end
  if fionread
    $defs << "-DFIONREAD_HEADER=\"<#{fionread}>\""
    create_makefile(target)
  end
end
