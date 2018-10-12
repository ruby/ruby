begin
  require_relative "lib/prime"
rescue LoadError
  # for Ruby core repository
  require_relative "prime"
end

Gem::Specification.new do |spec|
  spec.name          = "prime"
  spec.version       = Prime::VERSION
  spec.authors       = ["Yuki Sonoda"]
  spec.email         = ["yugui@yugui.jp"]

  spec.summary       = %q{Prime numbers and factorization library.}
  spec.description   = %q{Prime numbers and factorization library.}
  spec.homepage      = "https://github.com/ruby/prime"
  spec.license       = "BSD-2-Clause"

  spec.files         = [".gitignore", ".travis.yml", "Gemfile", "LICENSE.txt", "README.md", "Rakefile", "bin/console", "bin/setup", "lib/prime.rb", "lib/prime/version.rb", "prime.gemspec"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "test-unit"
end
