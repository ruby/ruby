if ENV['RUBYOPT'] or defined? Gem
  ENV.delete 'RUBYOPT'

  require 'rbconfig'
  cmd = [RbConfig.ruby, '--disable-gems', 'build.rb', *ARGV]

  exec(*cmd)
end

require 'tmpdir'

lp = File.expand_path('../../../../lib', __dir__)
gem = ["ruby", "-I#{lp}", File.expand_path('../../../../bin/gem', __dir__)]
gemspec = File.expand_path('rust_ruby_example.gemspec', __dir__)

Dir.mktmpdir("rust_ruby_example") do |dir|
  built_gem = File.expand_path(File.join(dir, "rust_ruby_example.gem"))
  system(*gem, "build", gemspec, "--output", built_gem)
  system(*gem, "install", "--verbose", "--local", built_gem, *ARGV)
  system %q(ruby -rrust_ruby_example -e "puts 'Result: ' + RustRubyExample.reverse('hello world')")
end
