# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'did_you_mean/version'

Gem::Specification.new do |spec|
  spec.name          = "did_you_mean"
  spec.version       = DidYouMean::VERSION
  spec.authors       = ["Yuki Nishijima"]
  spec.email         = ["mail@yukinishijima.net"]
  spec.summary       = '"Did you mean?" experience in Ruby'
  spec.description   = 'The gem that has been saving people from typos since 2014.'
  spec.homepage      = "https://github.com/ruby/did_you_mean"
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/).reject{|path| path.start_with?('evaluation/') }
  spec.test_files    = spec.files.grep(%r{^(test)/})
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.5.0'

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
end
