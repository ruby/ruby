#! ./miniruby

exit if defined?(CROSS_COMPILING) and CROSS_COMPILING
ruby = ENV["RUBY"]
unless ruby
  load './rbconfig.rb'
  ruby = "./#{RbConfig::CONFIG['ruby_install_name']}#{RbConfig::CONFIG['EXEEXT']}"
end
unless File.exist? ruby
  print "#{ruby} is not found.\n"
  print "Try `make' first, then `make test', please.\n"
  exit false
end
ARGV[0] and opt = ARGV[0][/\A--run-opt=(.*)/, 1] and ARGV.shift

$stderr.reopen($stdout)
error = ''

srcdir = File.expand_path('..', File.dirname(__FILE__))
if env = ENV["RUBYOPT"]
  ENV["RUBYOPT"] = env + " -W1"
end
`#{ruby} #{opt} -W1 #{srcdir}/basictest/test.rb #{ARGV.join(' ')}`.each_line do |line|
  if line =~ /^end of test/
    print "\ntest succeeded\n"
    exit true
  end
  error << line if %r:^(basictest/test.rb|not): =~ line
end
puts
print error
print "test failed\n"
exit false
