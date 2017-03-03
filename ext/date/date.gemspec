Gem::Specification.new do |s|
  s.name = "date"
  s.version = '0.0.1'
  s.date = '2017-02-02'
  s.summary = "A subclass of Object includes Comparable module for handling dates."
  s.description = "A subclass of Object includes Comparable module for handling dates."

  s.require_path = %w{lib}
  s.files = %w{lib/date.rb date_core.c date_parse.c date_strftime.c date_strptime.c date_tmx.h depend extconf.rb prereq.mk zonetab.h zonetab.list}
  s.extensions = %w{extconf.rb}
  s.required_ruby_version = ">= 2.5.0dev"

  s.authors = ["Tadayoshi Funaba"]
  s.email = [nil]
  s.homepage = "https://www.ruby-lang.org"
  s.license = "BSD-2-Clause"
end
