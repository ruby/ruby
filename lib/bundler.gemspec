# coding: utf-8
# frozen_string_literal: true
lib = File.expand_path("../lib/", __FILE__)
$:.unshift lib unless $:.include?(lib)
require "bundler/version"

Gem::Specification.new do |s|
  s.name        = "bundler"
  s.version     = Bundler::VERSION
  s.license     = "MIT"
  s.authors     = [
    "André Arko", "Samuel Giddins", "Chris Morris", "James Wen", "Tim Moore",
    "André Medeiros", "Jessica Lynn Suttles", "Terence Lee", "Carl Lerche",
    "Yehuda Katz"
  ]
  s.email       = ["team@bundler.io"]
  s.homepage    = "http://bundler.io"
  s.summary     = "The best way to manage your application's dependencies"
  s.description = "Bundler manages an application's dependencies through its entire life, across many machines, systematically and repeatably"

  if s.respond_to?(:metadata=)
    s.metadata = {
      "bug_tracker_uri" => "http://github.com/bundler/bundler/issues",
      "changelog_uri" => "https://github.com/bundler/bundler/blob/master/CHANGELOG.md",
      "homepage_uri" => "https://bundler.io/",
      "source_code_uri" => "http://github.com/bundler/bundler/",
    }
  end

  s.required_ruby_version     = ">= 1.8.7"
  s.required_rubygems_version = ">= 1.3.6"

  s.add_development_dependency "automatiek", "~> 0.1.0"
  s.add_development_dependency "mustache",   "0.99.6"
  s.add_development_dependency "rake",       "~> 10.0"
  s.add_development_dependency "rdiscount",  "~> 2.2"
  s.add_development_dependency "ronn",       "~> 0.7.3"
  s.add_development_dependency "rspec",      "~> 3.5"

  s.files = `git ls-files -z`.split("\x0").reject {|f| f.match(%r{^(test|spec|features)/}) }
  # we don't check in man pages, but we need to ship them because
  # we use them to generate the long-form help for each command.
  s.files += Dir.glob("man/**/*")

  s.bindir        = "exe"
  s.executables   = %w(bundle bundler)
  s.require_paths = ["lib"]
end
