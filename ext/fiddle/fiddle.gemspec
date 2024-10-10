# frozen_string_literal: true

version_module = Module.new do
  version_rb = File.join(__dir__, "lib/fiddle/version.rb")
  module_eval(File.read(version_rb), version_rb, __LINE__)
end

Gem::Specification.new do |spec|
  spec.name          = "fiddle"
  spec.version       = version_module::Fiddle::VERSION
  spec.authors       = ["Aaron Patterson", "SHIBATA Hiroshi"]
  spec.email         = ["aaron@tenderlovemaking.com", "hsbt@ruby-lang.org"]

  spec.summary       = %q{A libffi wrapper for Ruby.}
  spec.description   = %q{A libffi wrapper for Ruby.}
  spec.homepage      = "https://github.com/ruby/fiddle"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.files         = [
    "LICENSE.txt",
    "README.md",
    "Rakefile",
    "ext/fiddle/closure.c",
    "ext/fiddle/closure.h",
    "ext/fiddle/conversions.c",
    "ext/fiddle/conversions.h",
    "ext/fiddle/depend",
    "ext/fiddle/extconf.rb",
    "ext/fiddle/fiddle.c",
    "ext/fiddle/fiddle.h",
    "ext/fiddle/function.c",
    "ext/fiddle/function.h",
    "ext/fiddle/handle.c",
    "ext/fiddle/memory_view.c",
    "ext/fiddle/pinned.c",
    "ext/fiddle/pointer.c",
    "fiddle.gemspec",
    "lib/fiddle.rb",
    "lib/fiddle/closure.rb",
    "lib/fiddle/cparser.rb",
    "lib/fiddle/ffi_backend.rb",
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

  spec.required_ruby_version = ">= 2.5.0"

  spec.metadata["msys2_mingw_dependencies"] = "libffi"
  spec.metadata["changelog_uri"] = "https://github.com/ruby/fiddle/releases"
end
