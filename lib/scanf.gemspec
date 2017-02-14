Gem::Specification.new do |s|
  s.name = "scanf"
  s.version = '0.0.1'
  s.date = '2017-02-14'
  s.summary = "scanf is an implementation of the C function scanf(3)."
  s.description = "scanf is an implementation of the C function scanf(3)."

  s.require_path = %w{lib}
  s.files = %w{scanf.rb}
  s.required_ruby_version = ">= 2.5.0dev"

  s.authors = ["David Alan Black"]
  s.email = ['dblack@superlink.net']
  s.homepage = "https://www.ruby-lang.org"
  s.license = "BSD-2-Clause"
end
