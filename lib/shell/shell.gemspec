begin
  require_relative "lib/shell/version"
rescue LoadError
  # for Ruby core repository
  require_relative "version"
end

Gem::Specification.new do |spec|
  spec.name          = "shell"
  spec.version       = Shell::VERSION
  spec.authors       = ["Keiju ISHITSUKA"]
  spec.email         = ["keiju@ruby-lang.org"]

  spec.summary       = %q{An idiomatic Ruby interface for common UNIX shell commands.}
  spec.description   = %q{An idiomatic Ruby interface for common UNIX shell commands.}
  spec.homepage      = "https://github.com/ruby/shell"
  spec.license       = "BSD-2-Clause"

  spec.files         = [".gitignore", ".travis.yml", "Gemfile", "LICENSE.txt", "README.md", "Rakefile", "bin/console", "bin/setup", "lib/shell.rb", "lib/shell/builtin-command.rb", "lib/shell/command-processor.rb", "lib/shell/error.rb", "lib/shell/filter.rb", "lib/shell/process-controller.rb", "lib/shell/system-command.rb", "lib/shell/version.rb", "shell.gemspec"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
end
