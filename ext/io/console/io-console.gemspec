# -*- ruby -*-
_VERSION = "0.6.0"

Gem::Specification.new do |s|
  s.name = "io-console"
  s.version = _VERSION
  s.summary = "Console interface"
  s.email = "nobu@ruby-lang.org"
  s.description = "add console capabilities to IO instances."
  s.required_ruby_version = ">= 2.6.0"
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

  if Gem::Platform === s.platform and s.platform =~ 'java'
    s.files.delete_if {|f| f.start_with?("ext/")}
    s.extensions.clear
    s.files.concat(%w[
      lib/io/console.rb
      lib/io/console/ffi/bsd_console.rb
      lib/io/console/ffi/common.rb
      lib/io/console/ffi/console.rb
      lib/io/console/ffi/linux_console.rb
      lib/io/console/ffi/native_console.rb
      lib/io/console/ffi/stty_console.rb
      lib/io/console/ffi/stub_console.rb
    ])
  end

  s.licenses = ["Ruby", "BSD-2-Clause"]
end
