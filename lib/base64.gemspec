Gem::Specification.new do |spec|
  spec.name          = "base64"
  spec.version       = "0.1.1"
  spec.authors       = ["Yusuke Endoh"]
  spec.email         = ["mame@ruby-lang.org"]

  spec.summary       = %q{Support for encoding and decoding binary data using a Base64 representation.}
  spec.description   = %q{Support for encoding and decoding binary data using a Base64 representation.}
  spec.homepage      = "https://github.com/ruby/base64"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.3.0")
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = ["README.md", "LICENSE.txt", "lib/base64.rb"]
  spec.bindir        = "exe"
  spec.executables   = []
  spec.require_paths = ["lib"]
end
