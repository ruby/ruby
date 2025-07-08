Gem::Specification.new do |spec|
  spec.name          = "resolv"
  spec.version       = "0.2.3"
  spec.authors       = ["Tanaka Akira"]
  spec.email         = ["akr@fsij.org"]

  spec.summary       = %q{Thread-aware DNS resolver library in Ruby.}
  spec.description   = %q{Thread-aware DNS resolver library in Ruby.}
  spec.homepage      = "https://github.com/ruby/resolv"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = []
  spec.require_paths = ["lib"]
end
