#! ./miniruby
require 'rbconfig'
include Config

$stderr.reopen($stdout)
error = ''
`./ruby #{CONFIG["srcdir"]}/sample/test.rb`.each do |line|
  if line =~ /^end of test/
    print "test succeeded\n"
    exit 0
  end
  error << line if line =~ %r:^(sample/test.rb|not):
end
print error
print "test failed\n"
