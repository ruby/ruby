# frozen_string_literal: true
Gem::Specification.new do |s|
  s.name = "strscan"
  s.version = '0.0.1'
  s.date = '2017-02-07'
  s.summary = "Provides lexical scanning operations on a String."
  s.description = "Provides lexical scanning operations on a String."

  s.require_path = %w{lib}
  s.files = %w{ext/strscan/extconf.rb ext/strscan/strscan.c ext/strscan/regenc.h ext/strscan/regint.h}
  s.extensions = %w{extconf.rb}
  s.required_ruby_version = ">= 2.5.0dev"

  s.authors = ["Minero Aoki"]
  s.email = [nil]
  s.homepage = "https://github.com/ruby/strscan"
  s.license = "BSD-2-Clause"

  s.add_development_dependency "rake-compiler"
end
