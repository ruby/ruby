# -*- ruby -*-
_VERSION = "0.5.6"

Gem::Specification.new do |s|
  s.name = "io-console"
  s.version = _VERSION
  s.summary = "Console interface"
  s.email = "nobu@ruby-lang.org"
  s.description = "add console capabilities to IO instances."
  s.required_ruby_version = ">= 2.4.0"
  s.homepage = "https://github.com/ruby/io-console"
  s.metadata["source_code_url"] = s.homepage
  s.authors = ["Nobu Nakada"]
  s.require_path = %[lib]
  s.files = %w[
    LICENSE.txt
    README.md
    ext/io/console/console.c
    ext/io/console/extconf.rb
    ext/io/console/win32_vk.inc
    lib/io/console/size.rb
  ]
  s.extensions = %w[ext/io/console/extconf.rb]
  s.licenses = ["Ruby", "BSD-2-Clause"]
end
