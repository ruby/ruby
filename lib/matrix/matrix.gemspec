# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "matrix"
  spec.version       = "0.1.0"
  spec.authors       = ["Marc-Andre Lafortune"]
  spec.email         = ["ruby-core@marc-andre.ca"]

  spec.summary       = %q{An implementation of Matrix and Vector classes.}
  spec.description   = %q{An implementation of Matrix and Vector classes.}
  spec.homepage      = "https://github.com/ruby/matrix"
  spec.license       = "BSD-2-Clause"

  spec.files         = [".gitignore", ".travis.yml", "Gemfile", "LICENSE.txt", "README.md", "Rakefile", "bin/console", "bin/setup", "lib/matrix.rb", "matrix.gemspec"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
end
