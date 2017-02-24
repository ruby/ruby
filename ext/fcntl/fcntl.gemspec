Gem::Specification.new do |s|
  s.name = "fcntl"
  s.version = '0.0.1'
  s.date = '2017-02-10'
  s.summary = "Loads constants defined in the OS fcntl.h C header file"
  s.description = "Loads constants defined in the OS fcntl.h C header file"

  s.require_path = %w{lib}
  s.files = %w{depend extconf.rb fcntl.c}
  s.extensions = %w{extconf.rb}
  s.required_ruby_version = ">= 2.5.0dev"

  s.authors = ["Yukihiro Matsumoto"]
  s.email = ["matz@ruby-lang.org"]
  s.homepage = "https://www.ruby-lang.org"
  s.license = "BSD-2-Clause"
end
