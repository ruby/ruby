#! ./miniruby -I.

require 'rbconfig'
include Config

if File.exist? CONFIG['LIBRUBY_SO']
  case RUBY_PLATFORM
  when /-hpux/
    dldpath = "SHLIB_PATH"
  when /-aix/
    dldpath = "LIBPATH"
  else
    dldpath = "LD_LIBRARY_PATH"
  end
  x = ENV[dldpath]
  x = x ? ".:"+x : "."
  ENV[dldpath] = x
end

if /linux/ =~ RUBY_PLATFORM and File.exist? CONFIG['LIBRUBY_SO']
  ENV["LD_PRELOAD"] = "./#{CONFIG['LIBRUBY_SO']}"
end

$stderr.reopen($stdout)
error = ''
`./#{CONFIG["ruby_install_name"]} #{CONFIG["srcdir"]}/sample/test.rb`.each do |line|
  if line =~ /^end of test/
    print "test succeeded\n"
    exit 0
  end
  error << line if line =~ %r:^(sample/test.rb|not):
end
print error
print "test failed\n"
