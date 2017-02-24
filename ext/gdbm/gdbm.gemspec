Gem::Specification.new do |s|
  s.name = "gdbm"
  s.version = '0.0.1'
  s.date = '2017-02-24'
  s.summary = "Ruby extension for GNU dbm."
  s.description = "Ruby extension for GNU dbm."

  s.require_path = %w{lib}
  s.files = %w{depend extconf.rb gdbm.c}
  s.extensions = %w{extconf.rb}
  s.required_ruby_version = ">= 2.5.0dev"

  s.authors = ["Yukihiro Matsumoto"]
  s.email = ["matz@ruby-lang.org"]
  s.homepage = "https://www.ruby-lang.org"
  s.license = "BSD-2-Clause"
end
