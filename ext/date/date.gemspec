# frozen_string_literal: true
Gem::Specification.new do |s|
  s.name = "date"
  s.version = '3.0.0'
  s.summary = "A subclass of Object includes Comparable module for handling dates."
  s.description = "A subclass of Object includes Comparable module for handling dates."

  s.require_path = %w{lib}
  s.files = [
    "lib/date.rb", "ext/date/date_core.c", "ext/date/date_parse.c", "ext/date/date_strftime.c",
    "ext/date/date_strptime.c", "ext/date/date_tmx.h", "ext/date/extconf.rb", "ext/date/prereq.mk",
    "ext/date/zonetab.h", "ext/date/zonetab.list"
  ]
  s.extensions = "ext/date/extconf.rb"
  s.required_ruby_version = ">= 2.4.0"

  s.authors = ["Tadayoshi Funaba"]
  s.email = [nil]
  s.homepage = "https://github.com/ruby/date"
  s.license = "BSD-2-Clause"
end
