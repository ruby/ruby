begin
  require_relative "lib/thwait/version"
rescue LoadError
  # for Ruby core repository
  require_relative "version"
end

Gem::Specification.new do |spec|
  spec.name          = "thwait"
  spec.version       = ThreadsWait::VERSION
  spec.authors       = ["Keiju ISHITSUKA"]
  spec.email         = ["keiju@ruby-lang.org"]

  spec.summary       = %q{Watches for termination of multiple threads.}
  spec.description   = %q{Watches for termination of multiple threads.}
  spec.homepage      = "https://github.com/ruby/thwait"
  spec.license       = "BSD-2-Clause"

  spec.files         = [".gitignore", "Gemfile", "LICENSE.txt", "README.md", "Rakefile", "bin/console", "bin/setup", "lib/thwait.rb", "lib/thwait/version.rb", "thwait.gemspec"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
end
