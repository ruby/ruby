Gem::Specification.new do |s|
  s.name = "dbm"
  s.version = '0.0.1'
  s.date = '2017-02-08'
  s.summary = "Provides a wrapper for the UNIX-style Database Manager Library"
  s.description = "Provides a wrapper for the UNIX-style Database Manager Library"

  s.require_path = %w{lib}
  s.files = %w{depend extconf.rb dbm.c}
  s.extensions = %w{extconf.rb}
  s.required_ruby_version = ">= 2.5.0dev"

  s.authors = ["Yukihiro Matsumoto"]
  s.email = ["matz@ruby-lang.org"]
  s.homepage = "https://www.ruby-lang.org"
  s.license = "BSD-2-Clause"
end
