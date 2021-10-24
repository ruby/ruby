# coding: utf-8
# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "digest"
  spec.version       = "3.1.0.pre2"
  spec.authors       = ["Akinori MUSHA"]
  spec.email         = ["knu@idaemons.org"]

  spec.summary       = %q{Provides a framework for message digest libraries.}
  spec.description   = %q{Provides a framework for message digest libraries.}
  spec.homepage      = "https://github.com/ruby/digest"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.files = [
    "LICENSE.txt",
    "README.md",
    *Dir["lib/digest{.rb,/**/*.rb}"],
  ]

  spec.required_ruby_version = ">= 2.5.0"

  spec.bindir        = "exe"
  spec.executables   = []

  if Gem::Platform === spec.platform and spec.platform =~ 'java' or RUBY_ENGINE == 'jruby'
    spec.platform = 'java'

    spec.files += Dir["ext/java/**/*.{rb,java}", "lib/digest.jar"]
    spec.require_paths = %w[lib ext/java/org/jruby/ext/digest/lib]
  else
    spec.extensions = Dir["ext/digest/**/extconf.rb"]

    spec.files += Dir["ext/digest/**/*.{rb,c,h,sh}"]
    spec.require_paths = %w[lib]
  end

  spec.metadata["msys2_mingw_dependencies"] = "openssl"
end
