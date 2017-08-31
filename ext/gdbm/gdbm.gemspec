# coding: utf-8
# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "gdbm"
  spec.version       = "2.0.0.beta1"
  spec.date          = '2017-04-28'
  spec.authors       = ["Yukihiro Matsumoto"]
  spec.email         = ["matz@ruby-lang.org"]

  spec.summary       = "Ruby extension for GNU dbm."
  spec.description   = "Ruby extension for GNU dbm."
  spec.homepage      = "https://github.com/ruby/gdbm"
  spec.license       = "BSD-2-Clause"

  spec.files         = ["ext/gdbm/extconf.rb", "ext/gdbm/gdbm.c"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.extensions    = ["ext/gdbm/extconf.rb"]
  spec.required_ruby_version = ">= 2.5.0dev"

  spec.add_development_dependency "bundler", "~> 1.14"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rake-compiler"
  spec.add_development_dependency "test-unit"
end
