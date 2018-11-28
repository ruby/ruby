# -*- encoding: utf-8 -*-
# frozen_string_literal: true
# stub: stringio 0.0.0 ruby lib
# stub: extconf.rb

Gem::Specification.new do |s|
  s.name = "stringio".freeze
  s.version = "0.0.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 2.6".freeze)
  s.require_paths = ["lib".freeze]
  s.authors = ["Nobu Nakada".freeze]
  s.description = "Pseudo `IO` class from/to `String`.".freeze
  s.email = "nobu@ruby-lang.org".freeze
  s.extensions = ["ext/stringio/extconf.rb".freeze]
  s.files = ["README.md".freeze, "ext/stringio/extconf.rb".freeze, "ext/stringio/stringio.c".freeze]
  s.homepage = "https://github.com/ruby/stringio".freeze
  s.licenses = ["BSD-2-Clause".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 2.2".freeze)
  s.rubygems_version = "2.6.11".freeze
  s.summary = "Pseudo IO on String".freeze

  # s.cert_chain  = %w[certs/nobu.pem]
  # s.signing_key = File.expand_path("~/.ssh/gem-private_key.pem") if $0 =~ /gem\z/

  s.add_development_dependency 'rake-compiler'
end
