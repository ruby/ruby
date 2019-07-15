begin
  require_relative "lib/e2mmap/version"
rescue LoadError
  # for Ruby core repository
  require_relative "e2mmap/version"
end

Gem::Specification.new do |spec|
  spec.name          = "e2mmap"
  spec.version       = Exception2MessageMapper::VERSION
  spec.authors       = ["Keiju ISHITSUKA"]
  spec.email         = ["keiju@ruby-lang.org"]

  spec.summary       = %q{Module for defining custom exceptions with specific messages.}
  spec.description   = %q{Module for defining custom exceptions with specific messages.}
  spec.homepage      = "https://github.com/ruby/e2mmap"
  spec.license       = "BSD-2-Clause"

  spec.files         = [".gitignore", "Gemfile", "LICENSE.txt", "README.md", "Rakefile", "bin/console", "bin/setup", "e2mmap.gemspec", "lib/e2mmap.rb", "lib/e2mmap/version.rb"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
end
