Gem::Specification.new do |s|
  s.name = "sdbm"
  s.version = '0.0.1'
  s.date = '2017-02-28'
  s.summary = "Provides a simple file-based key-value store with String keys and values."
  s.description = "Provides a simple file-based key-value store with String keys and values."

  s.require_path = %w{lib}
  s.files = %w{_sdbm.c depend extconf.rb init.c sdbm.h}
  s.extensions = %w{extconf.rb}
  s.required_ruby_version = ">= 2.5.0dev"

  s.authors = ["Yukihiro Matsumoto"]
  s.email = ["matz@ruby-lang.org"]
  s.homepage = "https://www.ruby-lang.org"
  s.license = "BSD-2-Clause"
end
