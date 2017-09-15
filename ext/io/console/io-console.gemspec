# -*- ruby -*-
_VERSION = "0.4.6"
date = %w$Date::                           $[1]

Gem::Specification.new do |s|
  s.name = "io-console"
  s.version = _VERSION
  s.date = date
  s.summary = "Console interface"
  s.email = "nobu@ruby-lang.org"
  s.description = "add console capabilities to IO instances."
  s.required_ruby_version = ">= 2.0.0"
  s.homepage = "https://github.com/ruby/io-console"
  s.authors = ["Nobu Nakada"]
  s.require_path = %[lib]
  s.files = %w[ext/io/console/console.c ext/io/console/extconf.rb lib/console/size.rb ext/io/console/win32_vk.inc]
  s.extensions = %w[ext/io/console/extconf.rb]
  s.license = "BSD-2-Clause"
  s.cert_chain  = %w[certs/nobu.pem]
  s.signing_key = File.expand_path("~/.ssh/gem-private_key.pem") if $0 =~ /gem\z/

  s.add_development_dependency 'rake-compiler'
  s.add_development_dependency 'rake-compiler-dock', ">= 0.6.1"
end
