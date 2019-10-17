begin
  require_relative "lib/forwardable"
rescue LoadError
  # for Ruby core repository
  require_relative "../forwardable"
end

Gem::Specification.new do |spec|
  spec.name          = "forwardable"
  spec.version       = Forwardable::VERSION
  spec.authors       = ["Keiju ISHITSUKA"]
  spec.email         = ["keiju@ruby-lang.org"]

  spec.summary       = %q{Provides delegation of specified methods to a designated object.}
  spec.description   = %q{Provides delegation of specified methods to a designated object.}
  spec.homepage      = "https://github.com/ruby/forwardable"
  spec.license       = "BSD-2-Clause"

  spec.files         = [".gitignore", ".travis.yml", "Gemfile", "LICENSE.txt", "README.md", "Rakefile", "bin/console", "bin/setup", "forwardable.gemspec", "lib/forwardable.rb", "lib/forwardable/impl.rb"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
end
