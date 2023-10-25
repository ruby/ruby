# frozen_string_literal: true

version = File.foreach(File.expand_path("../lib/date.rb", __FILE__)).find do |line|
  /^\s*VERSION\s*=\s*["'](.*)["']/ =~ line and break $1
end

Gem::Specification.new do |s|
  s.name = "date"
  s.version = version
  s.summary = "A subclass of Object includes Comparable module for handling dates."
  s.description = "A subclass of Object includes Comparable module for handling dates."

  if Gem::Platform === s.platform and s.platform =~ 'java' or RUBY_ENGINE == 'jruby'
    s.platform = 'java'
    # No files shipped, no require path, no-op for now on JRuby
  else
    s.require_path = %w{lib}

    s.files = [
      "README.md",
      "lib/date.rb", "ext/date/date_core.c", "ext/date/date_parse.c", "ext/date/date_strftime.c",
      "ext/date/date_strptime.c", "ext/date/date_tmx.h", "ext/date/extconf.rb", "ext/date/prereq.mk",
      "ext/date/zonetab.h", "ext/date/zonetab.list"
    ]
    s.extensions = "ext/date/extconf.rb"
  end

  s.required_ruby_version = ">= 2.6.0"

  s.authors = ["Tadayoshi Funaba"]
  s.email = [nil]
  s.homepage = "https://github.com/ruby/date"
  s.licenses = ["Ruby", "BSD-2-Clause"]
end
