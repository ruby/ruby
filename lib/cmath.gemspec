# coding: utf-8
# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "cmath"
  spec.version       = "1.0.0"
  spec.authors       = ["Tadayoshi Funaba"]
  spec.email         = [nil]

  spec.summary       = "Provides Trigonometric and Transcendental functions for complex numbers"
  spec.description   = "CMath is a library that provides trigonometric and transcendental functions for complex numbers. The functions in this module accept integers, floating-point numbers or complex numbers as arguments."
  spec.homepage      = "https://github.com/ruby/cmath"
  spec.license       = "BSD-2-Clause"

  spec.files         = "lib/cmath.rb"
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 2.3.0"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
end
