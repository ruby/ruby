# frozen_string_literal: true

begin
  require_relative "lib/syntax_suggest/version"
rescue LoadError # Fallback to load version file in ruby core repository
  require_relative "version"
end

Gem::Specification.new do |spec|
  spec.name = "syntax_suggest"
  spec.version = SyntaxSuggest::VERSION
  spec.authors = ["schneems"]
  spec.email = ["richard.schneeman+foo@gmail.com"]

  spec.summary = "Find syntax errors in your source in a snap"
  spec.description = 'When you get an "unexpected end" in your syntax this gem helps you find it'
  spec.homepage = "https://github.com/ruby/syntax_suggest.git"
  spec.license = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.0.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ruby/syntax_suggest.git"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path("..", __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features|assets)/}) }
  end
  spec.bindir = "exe"
  spec.executables = ["syntax_suggest"]
  spec.require_paths = ["lib"]
end
