# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "ruby-signature-amber"
  spec.version       = "1.0.0"
  spec.authors       = ["Soutaro Matsumoto"]
  spec.email         = ["matsumoto@soutaro.com"]

  spec.summary       = %q{Test Gem}
  spec.description   = %q{Test Gem with RBS files}
  spec.homepage      = "https://example.com"
  spec.license       = 'MIT'

  spec.files         = [
    "lib/amber.rb",
    "sig/amber.rbs"
  ]
  spec.require_paths = ["lib"]
end
