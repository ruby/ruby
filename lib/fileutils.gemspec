# frozen_string_literal: true
Gem::Specification.new do |s|
  s.name = "fileutils"
  s.version = '0.7.2'
  s.date = '2017-02-06'
  s.summary = "Several file utility methods for copying, moving, removing, etc."
  s.description = "Several file utility methods for copying, moving, removing, etc."

  s.require_path = %w{lib}
  s.files = [".gitignore", ".travis.yml", "Gemfile", "LICENSE.txt", "README.md", "Rakefile", "bin/console", "bin/setup", "fileutils.gemspec", "lib/fileutils.rb"]
  s.required_ruby_version = ">= 2.5.0dev"

  s.authors = ["Minero Aoki"]
  s.email = [nil]
  s.homepage = "https://github.com/ruby/fileutils"
  s.license = "BSD-2-Clause"

  s.add_development_dependency 'rake'
end
