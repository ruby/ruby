Gem::Specification.new do |spec|
  spec.name          = "tmpdir"
  spec.version       = "0.1.2"
  spec.authors       = ["Yukihiro Matsumoto"]
  spec.email         = ["matz@ruby-lang.org"]

  spec.summary       = %q{Extends the Dir class to manage the OS temporary file path.}
  spec.description   = %q{Extends the Dir class to manage the OS temporary file path.}
  spec.homepage      = "https://github.com/ruby/tmpdir"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z 2>/dev/null`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "fileutils"
end
