require 'mkmf'
target = "io/wait"

unless /djgpp|mswin|mingw|human/ =~ RUBY_PLATFORM
  fionread = %w[sys/ioctl.h sys/filio.h].find do |h|
    checking_for("FIONREAD") {macro_defined?("FIONREAD", "#include <#{h}>\n")}
  end
  if fionread
    $defs << "-DFIONREAD_HEADER=\"<#{fionread}>\""
    create_makefile(target)
  end
end
