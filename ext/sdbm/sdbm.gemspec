# frozen_string_literal: true
Gem::Specification.new do |s|
  s.name = "sdbm"
  s.version = '0.0.1'
  s.date = '2017-02-28'
  s.summary = "Provides a simple file-based key-value store with String keys and values."
  s.description = "Provides a simple file-based key-value store with String keys and values."

  s.require_path = %w{lib}
  s.files = %w{ext/sdbm/_sdbm.c ext/sdbm/depend ext/sdbm/extconf.rb ext/sdbm/init.c ext/sdbm/sdbm.h}
  s.extensions = ["ext/sdbm/extconf.rb"]
  s.required_ruby_version = ">= 2.5.0dev"

  s.authors = ["Yukihiro Matsumoto"]
  s.email = ["matz@ruby-lang.org"]
  s.homepage = "https://github.com/ruby/sdbm"
  s.license = "BSD-2-Clause"

  s.add_development_dependency "test-unit"
  s.add_development_dependency "rake-compiler"
end
