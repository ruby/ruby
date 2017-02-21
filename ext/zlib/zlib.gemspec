Gem::Specification.new do |s|
  s.name = "zlib"
  s.version = '0.0.1'
  s.date = '2017-02-03'
  s.summary = "An interface for zlib."
  s.description = "An interface for zlib."

  s.require_path = %w{lib}
  s.files = %w{depend extconf.rb zlib.c}
  s.extensions = %w{extconf.rb}
  s.required_ruby_version = ">= 2.5.0dev"

  s.authors = ["UENO Katsuhiro"]
  s.email = [nil]
  s.homepage = "https://www.ruby-lang.org"
  s.license = "BSD-2-Clause"
end
