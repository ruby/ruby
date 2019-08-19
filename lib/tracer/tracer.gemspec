begin
  require_relative "lib/tracer/version"
rescue LoadError
  # for Ruby core repository
  require_relative "version"
end

Gem::Specification.new do |spec|
  spec.name          = "tracer"
  spec.version       = Tracer::VERSION
  spec.authors       = ["Keiju ISHITSUKA"]
  spec.email         = ["keiju@ruby-lang.org"]

  spec.summary       = %q{Outputs a source level execution trace of a Ruby program.}
  spec.description   = %q{Outputs a source level execution trace of a Ruby program.}
  spec.homepage      = "https://github.com/ruby/tracer"
  spec.license       = "BSD-2-Clause"

  spec.files         = [".gitignore", ".travis.yml", "Gemfile", "LICENSE.txt", "README.md", "Rakefile", "bin/console", "bin/setup", "lib/tracer.rb", "lib/tracer/version.rb", "tracer.gemspec"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
end
