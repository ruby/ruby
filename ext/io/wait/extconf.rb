require 'mkmf'
target = "io/wait"
unless defined?(checking_for)
  def checking_for(msg)
    STDOUT.print "checking for ", msg, "..."
    STDOUT.flush
    STDOUT.puts((r = yield) ? "yes" : "no")
    r
  end
end
unless defined?(macro_defined?)
  def macro_defined?(macro, src, opt="")
    try_cpp(src + <<"SRC", opt)
#ifndef #{macro}
# error
#endif
SRC
  end
end

unless /djgpp|mswin|mingw|human/ =~ RUBY_PLATFORM
  fionread = %w[sys/ioctl.h sys/filio.h].find do |h|
    checking_for("FIONREAD") {macro_defined?("FIONREAD", "#include <#{h}>\n")}
  end
  exit 1 unless fionread
  $defs << "-DFIONREAD_HEADER=\"<#{fionread}>\""
  create_makefile(target)
end
