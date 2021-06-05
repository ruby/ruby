# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "un"
  spec.version       = "0.1.0"
  spec.authors       = ["WATANABE Hirofumi"]
  spec.email         = ["eban@ruby-lang.org"]

  spec.summary       = "Utilities to replace common UNIX commands"
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/ruby/un"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
