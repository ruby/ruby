Gem::Specification.new do |s|
  s.name = "etc"
  s.version = '0.0.1'
  s.date = '2017-02-27'
  s.summary = "Provides access to information typically stored in UNIX /etc directory."
  s.description = "Provides access to information typically stored in UNIX /etc directory."

  s.require_path = %w{lib}
  s.files = %w{depend extconf.rb etc.c mkconstants.rb}
  s.extensions = %w{extconf.rb}
  s.required_ruby_version = ">= 2.5.0dev"

  s.authors = ["Yukihiro Matsumoto"]
  s.email = ["matz@ruby-lang.org"]
  s.homepage = "https://www.ruby-lang.org"
  s.license = "BSD-2-Clause"
end
