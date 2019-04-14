# frozen_string_literal: true

begin
  require File.expand_path("../lib/bundler/version", __FILE__)
rescue LoadError
  # for Ruby core repository
  require File.expand_path("../version", __FILE__)
end

Gem::Specification.new do |s|
  s.name        = "bundler"
  s.version     = Bundler::VERSION
  s.license     = "MIT"
  s.authors     = [
    "André Arko", "Samuel Giddins", "Colby Swandale", "Hiroshi Shibata",
    "David Rodríguez", "Grey Baker", "Stephanie Morillo", "Chris Morris", "James Wen", "Tim Moore",
    "André Medeiros", "Jessica Lynn Suttles", "Terence Lee", "Carl Lerche",
    "Yehuda Katz"
  ]
  s.email       = ["team@bundler.io"]
  s.homepage    = "https://bundler.io"
  s.summary     = "The best way to manage your application's dependencies"
  s.description = "Bundler manages an application's dependencies through its entire life, across many machines, systematically and repeatably"

  if s.respond_to?(:metadata=)
    s.metadata = {
      "bug_tracker_uri" => "https://github.com/bundler/bundler/issues",
      "changelog_uri" => "https://github.com/bundler/bundler/blob/master/CHANGELOG.md",
      "homepage_uri" => "https://bundler.io/",
      "source_code_uri" => "https://github.com/bundler/bundler/",
    }
  end

  if s.version >= Gem::Version.new("2.a".dup)
    s.required_ruby_version     = ">= 2.3.0"
    s.required_rubygems_version = ">= 2.5.0"
  else
    s.required_ruby_version     = ">= 1.8.7"
    s.required_rubygems_version = ">= 1.3.6"
  end

  s.add_development_dependency "automatiek", "~> 0.1.0"
  s.add_development_dependency "rake",       "~> 12.0"
  s.add_development_dependency "ronn",       "~> 0.7.3"
  s.add_development_dependency "rspec",      "~> 3.6"
  s.add_development_dependency "rubocop",    "= 0.65.0"

  # s.files = Dir.glob("{lib,exe}/**/*", File::FNM_DOTMATCH).reject {|f| File.directory?(f) }

  # we don't check in man pages, but we need to ship them because
  # we use them to generate the long-form help for each command.
  # s.files += Dir.glob("man/**/*")
  # Include the CHANGELOG.md, LICENSE.md, README.md manually
  # s.files += %w[CHANGELOG.md LICENSE.md README.md]
  # include the gemspec itself because warbler breaks w/o it
  s.files += %w[bundler.gemspec]

  s.bindir        = "exe"
  s.executables   = %w[bundle bundler]
  s.require_paths = ["lib"]
end
