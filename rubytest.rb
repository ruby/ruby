#! ./miniruby

load './rbconfig.rb'
include Config

unless File.exist? "./#{CONFIG['ruby_install_name']}#{CONFIG['EXEEXT']}"
  print "./#{CONFIG['ruby_install_name']} is not found.\n"
  print "Try `make' first, then `make test', please.\n"
  exit 1
end

if File.exist? CONFIG['LIBRUBY_SO']
  case RUBY_PLATFORM
  when /-hpux/
    dldpath = "SHLIB_PATH"
  when /-aix/
    dldpath = "LIBPATH"
  when /-beos/
    dldpath = "LIBRARY_PATH"
  when /-darwin/
    dldpath = "DYLD_LIBRARY_PATH"
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

`./#{CONFIG["ruby_install_name"]}#{CONFIG["EXEEXT"]} -I#{CONFIG["srcdir"]}/lib #{CONFIG["srcdir"]}/sample/test.rb`.each do |line|
  if line =~ /^end of test/
    print "test succeeded\n"
    exit 0
  end
  error << line if line =~ %r:^(sample/test.rb|not):
end
print error
print "test failed\n"
exit 1
