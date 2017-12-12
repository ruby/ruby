# frozen_string_literal: true
Gem::Specification.new do |s|
  s.name = "fileutils"
  s.version = '1.0.1'
  s.date = '2017-12-12'
  s.summary = "Several file utility methods for copying, moving, removing, etc."
  s.description = "Several file utility methods for copying, moving, removing, etc."

  s.require_path = %w{lib}
  s.files = [".gitignore", ".travis.yml", "Gemfile", "LICENSE.txt", "README.md", "Rakefile", "bin/console", "bin/setup", "fileutils.gemspec", "lib/fileutils.rb"]
  s.required_ruby_version = ">= 2.4.0"

  s.authors = ["Minero Aoki"]
  s.email = [nil]
  s.homepage = "https://github.com/ruby/fileutils"
  s.license = "BSD-2-Clause"

  if s.respond_to?(:metadata=)
    s.metadata = {
      "source_code_uri" => "https://github.com/ruby/fileutils"
    }
  end

  s.add_development_dependency 'rake'
end
