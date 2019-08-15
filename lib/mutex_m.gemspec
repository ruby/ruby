begin
  require_relative "lib/mutex_m"
rescue LoadError
  # for Ruby core repository
  require_relative "mutex_m"
end

Gem::Specification.new do |spec|
  spec.name          = "mutex_m"
  spec.version       = Mutex_m::VERSION
  spec.authors       = ["Keiju ISHITSUKA"]
  spec.email         = ["keiju@ruby-lang.org"]

  spec.summary       = %q{Mixin to extend objects to be handled like a Mutex.}
  spec.description   = %q{Mixin to extend objects to be handled like a Mutex.}
  spec.homepage      = "https://github.com/ruby/mutex_m"
  spec.license       = "BSD-2-Clause"

  spec.files         = [".gitignore", ".travis.yml", "Gemfile", "LICENSE.txt", "README.md", "Rakefile", "bin/console", "bin/setup", "lib/mutex_m.rb", "mutex_m.gemspec"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "test-unit"
end
