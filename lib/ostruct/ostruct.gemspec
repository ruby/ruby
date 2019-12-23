# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "ostruct"
  spec.version       = "0.1.0"
  spec.authors       = ["Marc-Andre Lafortune"]
  spec.email         = ["ruby-core@marc-andre.ca"]

  spec.summary       = %q{Class to build custom data structures, similar to a Hash.}
  spec.description   = %q{Class to build custom data structures, similar to a Hash.}
  spec.homepage      = "https://github.com/ruby/ostruct"
  spec.license       = "BSD-2-Clause"

  spec.files         = [".gitignore", ".travis.yml", "Gemfile", "LICENSE.txt", "README.md", "Rakefile", "bin/console", "bin/setup", "lib/ostruct.rb", "ostruct.gemspec"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
end
