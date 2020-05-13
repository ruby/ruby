# frozen_string_literal: true

begin
  require_relative "lib/fiddle/version"
rescue LoadError
  # for Ruby core repository
  require_relative "version"
end

Gem::Specification.new do |spec|
  spec.name          = "fiddle"
  spec.version       = Fiddle::VERSION
  spec.authors       = ["Aaron Patterson", "SHIBATA Hiroshi"]
  spec.email         = ["aaron@tenderlovemaking.com", "hsbt@ruby-lang.org"]

  spec.summary       = %q{A libffi wrapper for Ruby.}
  spec.description   = %q{A libffi wrapper for Ruby.}
  spec.homepage      = "https://github.com/ruby/fiddle"
  spec.license       = "BSD-2-Clause"

  spec.files         = [
    "LICENSE.txt",
    "README.md",
    "Rakefile",
    "ext/fiddle/closure.c",
    "ext/fiddle/closure.h",
    "ext/fiddle/conversions.c",
    "ext/fiddle/conversions.h",
    "ext/fiddle/extconf.rb",
    "ext/fiddle/extlibs",
    "ext/fiddle/fiddle.c",
    "ext/fiddle/fiddle.h",
    "ext/fiddle/function.c",
    "ext/fiddle/function.h",
    "ext/fiddle/handle.c",
    "ext/fiddle/pointer.c",
    "ext/fiddle/win32/fficonfig.h",
    "ext/fiddle/win32/libffi-3.2.1-mswin.patch",
    "ext/fiddle/win32/libffi-config.rb",
    "ext/fiddle/win32/libffi.mk.tmpl",
    "fiddle.gemspec",
    "lib/fiddle.rb",
    "lib/fiddle/closure.rb",
    "lib/fiddle/cparser.rb",
    "lib/fiddle/function.rb",
    "lib/fiddle/import.rb",
    "lib/fiddle/pack.rb",
    "lib/fiddle/struct.rb",
    "lib/fiddle/types.rb",
    "lib/fiddle/value.rb",
    "lib/fiddle/version.rb",
  ]
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/fiddle/extconf.rb"]

  spec.required_ruby_version = ">= 2.3.0"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rake-compiler"
end
