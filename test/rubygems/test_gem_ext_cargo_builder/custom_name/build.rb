if ENV['RUBYOPT'] or defined? Gem
  ENV.delete 'RUBYOPT'

  require 'rbconfig'
  cmd = [RbConfig.ruby, '--disable-gems', 'build.rb', *ARGV]

  exec(*cmd)
end

require 'tmpdir'

lp = File.expand_path("./../../../../../lib", __FILE__)
gem = ["ruby", "-I#{lp}", File.expand_path("./../../../../../bin/gem", __FILE__)]
gemspec = File.expand_path("./../custom_name.gemspec", __FILE__)

Dir.mktmpdir("custom_name") do |dir|
  built_gem = File.expand_path(File.join(dir, "custom_name.gem"))
  system *gem, "build", gemspec, "--output", built_gem
  system *gem, "install", "--verbose", "--local", built_gem, *ARGV
  system %q(ruby -rcustom_name -e "puts 'Result: ' + CustomName.say_hello")
end
