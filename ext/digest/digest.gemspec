# coding: utf-8
# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "digest"
  spec.version       = "3.0.0"
  spec.authors       = ["Akinori MUSHA"]
  spec.email         = ["knu@idaemons.org"]

  spec.summary       = %q{Provides a framework for message digest libraries.}
  spec.description   = %q{Provides a framework for message digest libraries.}
  spec.homepage      = "https://github.com/ruby/digest"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.files         = [
    "Gemfile", "LICENSE.txt", "README.md", "Rakefile", "bin/console", "bin/setup", "digest.gemspec",
    "ext/digest/bubblebabble/bubblebabble.c", "ext/digest/bubblebabble/extconf.rb", "ext/digest/defs.h",
    "ext/digest/digest.c", "ext/digest/digest.h", "ext/digest/digest_conf.rb", "ext/digest/extconf.rb",
    "ext/digest/md5/extconf.rb", "ext/digest/md5/md5.c", "ext/digest/md5/md5.h", "ext/digest/md5/md5cc.h",
    "ext/digest/md5/md5init.c", "ext/digest/rmd160/extconf.rb", "ext/digest/rmd160/rmd160.c",
    "ext/digest/rmd160/rmd160.h", "ext/digest/rmd160/rmd160init.c", "ext/digest/sha1/extconf.rb",
    "ext/digest/sha1/sha1.c", "ext/digest/sha1/sha1.h", "ext/digest/sha1/sha1cc.h",
    "ext/digest/sha1/sha1init.c", "ext/digest/sha2/extconf.rb", "ext/digest/sha2/lib/sha2.rb",
    "ext/digest/sha2/sha2.c", "ext/digest/sha2/sha2.h", "ext/digest/sha2/sha2cc.h",
    "ext/digest/sha2/sha2init.c", "ext/digest/test.sh", "ext/openssl/deprecation.rb",
    "lib/digest.rb"
  ]

  spec.required_ruby_version = ">= 2.3.0"

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.extensions    = %w[
    ext/digest/extconf.rb
    ext/digest/bubblebabble/extconf.rb
    ext/digest/md5/extconf.rb
    ext/digest/rmd160/extconf.rb
    ext/digest/sha1/extconf.rb
    ext/digest/sha2/extconf.rb
  ]
  spec.metadata["msys2_mingw_dependencies"] = "openssl"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rake-compiler"
end
