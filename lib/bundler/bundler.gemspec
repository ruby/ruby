# frozen_string_literal: true

begin
  require_relative "lib/bundler/version"
rescue LoadError
  # for Ruby core repository
  require_relative "version"
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

  s.required_ruby_version     = ">= 2.3.0"
  s.required_rubygems_version = ">= 2.5.2"

  s.files = (Dir.glob("lib/bundler/**/*", File::FNM_DOTMATCH) + Dir.glob("man/bundler*") + Dir.glob("libexec/bundle*")).reject {|f| File.directory?(f) }

  s.files += ["lib/bundler.rb"]

  s.bindir        = "libexec"
  s.executables   = %w[bundle bundler]
  s.require_paths = ["lib"]
end
