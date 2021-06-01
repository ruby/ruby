# frozen_string_literal: true

source_version = ["", "lib/"].find do |dir|
  begin
    break File.open(File.join(__dir__, "#{dir}fileutils.rb")) {|f|
      f.gets("\n  VERSION = ")
      f.gets[/\s*"(.+)"/, 1]
    }
  rescue Errno::ENOENT
  end
end

Gem::Specification.new do |s|
  s.name = "fileutils"
  s.version = source_version
  s.summary = "Several file utility methods for copying, moving, removing, etc."
  s.description = "Several file utility methods for copying, moving, removing, etc."

  s.require_path = %w{lib}
  s.files = ["LICENSE.txt", "README.md", "Rakefile", "fileutils.gemspec", "lib/fileutils.rb"]
  s.required_ruby_version = ">= 2.5.0"

  s.authors = ["Minero Aoki"]
  s.email = [nil]
  s.homepage = "https://github.com/ruby/fileutils"
  s.licenses = ["Ruby", "BSD-2-Clause"]

  s.metadata = {
    "source_code_uri" => "https://github.com/ruby/fileutils"
  }
end
