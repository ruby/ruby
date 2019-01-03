# frozen_string_literal: true

begin
  require_relative "lib/matrix/version"
rescue LoadError
  # for Ruby core repository
  require_relative "version"
end

Gem::Specification.new do |spec|
  spec.name          = "matrix"
  spec.version       = Matrix::VERSION
  spec.authors       = ["Marc-Andre Lafortune"]
  spec.email         = ["ruby-core@marc-andre.ca"]

  spec.summary       = %q{An implementation of Matrix and Vector classes.}
  spec.description   = %q{An implementation of Matrix and Vector classes.}
  spec.homepage      = "https://github.com/ruby/matrix"
  spec.license       = "BSD-2-Clause"

  spec.files         = [".gitignore", ".travis.yml", "Gemfile", "LICENSE.txt", "README.md", "Rakefile", "bin/console", "bin/setup", "lib/matrix.rb", "lib/matrix/eigenvalue_decomposition.rb", "lib/matrix/lup_decomposition.rb", "lib/matrix/version.rb", "matrix.gemspec"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
end
