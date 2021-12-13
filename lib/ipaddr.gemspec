# frozen_string_literal: true
# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "ipaddr"
  spec.version       = "1.2.3"
  spec.authors       = ["Akinori MUSHA", "Hajimu UMEMOTO"]
  spec.email         = ["knu@idaemons.org", "ume@mahoroba.org"]

  spec.summary       = %q{A class to manipulate an IP address in ruby}
  spec.description   = <<-'DESCRIPTION'
IPAddr provides a set of methods to manipulate an IP address.
Both IPv4 and IPv6 are supported.
  DESCRIPTION
  spec.homepage      = "https://github.com/ruby/ipaddr"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.files         = ["LICENSE.txt", "README.md", "ipaddr.gemspec", "lib/ipaddr.rb"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.3"
end
