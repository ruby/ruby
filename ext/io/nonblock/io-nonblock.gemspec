Gem::Specification.new do |spec|
  spec.name          = "io-nonblock"
  spec.version       = "0.3.1"
  spec.authors       = ["Nobu Nakada"]
  spec.email         = ["nobu@ruby-lang.org"]

  spec.summary       = %q{Enables non-blocking mode with IO class}
  spec.description   = %q{Enables non-blocking mode with IO class}
  spec.homepage      = "https://github.com/ruby/io-nonblock"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]
  spec.required_ruby_version = Gem::Requirement.new(">= 3.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files         = %w[
    COPYING
    README.md
    ext/io/nonblock/depend
    ext/io/nonblock/extconf.rb
    ext/io/nonblock/nonblock.c
  ]
  spec.extensions    = %w[ext/io/nonblock/extconf.rb]
  spec.require_paths = ["lib"]
end
