# frozen_string_literal: true

require_relative 'lib/dead_end/version'

Gem::Specification.new do |spec|
  spec.name          = "dead_end"
  spec.version       = DeadEnd::VERSION
  spec.authors       = ["schneems"]
  spec.email         = ["richard.schneeman+foo@gmail.com"]

  spec.summary       = %q{Find syntax errors in your source in a snap}
  spec.description   = %q{When you get an "unexpected end" in your syntax this gem helps you find it}
  spec.homepage      = "https://github.com/zombocom/dead_end.git"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.5.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/zombocom/dead_end.git"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features|assets)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
