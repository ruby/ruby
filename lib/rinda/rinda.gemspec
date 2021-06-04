Gem::Specification.new do |spec|
  spec.name          = "rinda"
  spec.version       = "0.1.0"
  spec.authors       = ["Masatoshi SEKI"]
  spec.email         = ["seki@ruby-lang.org"]

  spec.summary       = %q{The Linda distributed computing paradigm in Ruby.}
  spec.description   = %q{The Linda distributed computing paradigm in Ruby.}
  spec.homepage      = "https://github.com/ruby/rinda"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "drb"
  spec.add_dependency "ipaddr"
  spec.add_dependency "forwardable"
end
