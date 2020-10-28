# frozen_string_literal: true
# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "ipaddr"
  spec.version       = "1.2.2"
  spec.authors       = ["Akinori MUSHA", "Hajimu UMEMOTO"]
  spec.email         = ["knu@idaemons.org", "ume@mahoroba.org"]

  spec.summary       = %q{A class to manipulate an IP address in ruby}
  spec.description   = <<-'DESCRIPTION'
IPAddr provides a set of methods to manipulate an IP address.
Both IPv4 and IPv6 are supported.
  DESCRIPTION
  spec.homepage      = "https://github.com/ruby/ipaddr"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.files         = [".gitignore", ".travis.yml", "Gemfile", "LICENSE.txt", "README.md", "Rakefile", "bin/console", "bin/setup", "ipaddr.gemspec", "lib/ipaddr.rb"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.15"
  spec.add_development_dependency "rake", ">= 12.3.3"
  spec.add_development_dependency "test-unit"
end
