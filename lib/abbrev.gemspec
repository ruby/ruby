Gem::Specification.new do |spec|
  spec.name          = "abbrev"
  spec.version       = "0.1.1"
  spec.authors       = ["Akinori MUSHA"]
  spec.email         = ["knu@idaemons.org"]

  spec.summary       = %q{Calculates a set of unique abbreviations for a given set of strings}
  spec.description   = %q{Calculates a set of unique abbreviations for a given set of strings}
  spec.homepage      = "https://github.com/ruby/abbrev"
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
