#! ./miniruby -I.

x = ENV["LD_LIBRARY_PATH"]
x = x ? x+":." : "."
ENV["LD_LIBRARY_PATH"] = x

require 'rbconfig'
include Config

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
