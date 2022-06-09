# frozen_string_literal: true
# coding: utf-8

if File.exist?(File.expand_path("ipaddr.gemspec"))
  lib = File.expand_path("../lib", __FILE__)
  $LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

  file = File.expand_path("ipaddr.rb", lib)
else
  # for ruby-core
  file = File.expand_path("../ipaddr.rb", __FILE__)
end

version = File.foreach(file).find do |line|
  /^\s*VERSION\s*=\s*["'](.*)["']/ =~ line and break $1
end

Gem::Specification.new do |spec|
  spec.name          = "ipaddr"
  spec.version       = version
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
