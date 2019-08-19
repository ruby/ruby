begin
  require_relative "lib/logger/version"
rescue LoadError # Fallback to load version file in ruby core repository
  require_relative "version"
end

Gem::Specification.new do |spec|
  spec.name          = "logger"
  spec.version       = Logger::VERSION
  spec.authors       = ["SHIBATA Hiroshi"]
  spec.email         = ["hsbt@ruby-lang.org"]

  spec.summary       = %q{Provides a simple logging utility for outputting messages.}
  spec.description   = %q{Provides a simple logging utility for outputting messages.}
  spec.homepage      = "https://github.com/ruby/logger"
  spec.license       = "BSD-2-Clause"

  spec.files         = ["Gemfile", "LICENSE.txt", "README.md", "Rakefile", "lib/logger.rb", "logger.gemspec"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.3.0"

  spec.add_development_dependency "bundler", ">= 0"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
