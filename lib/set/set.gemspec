Gem::Specification.new do |spec|
  spec.name          = "set"
  spec.version       = "1.0.1"
  spec.authors       = ["Akinori MUSHA"]
  spec.email         = ["knu@idaemons.org"]

  spec.summary       = %q{Provides a class to deal with collections of unordered, unique values}
  spec.description   = %q{Provides a class to deal with collections of unordered, unique values}
  spec.homepage      = "https://github.com/ruby/set"
  spec.license       = "BSD-2-Clause"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/ruby/set/blob/v#{spec.version}/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
