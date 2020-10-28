# frozen_string_literal: true
Gem::Specification.new do |s|
  s.name = "strscan"
  s.version = "1.0.4"
  s.summary = "Provides lexical scanning operations on a String."
  s.description = "Provides lexical scanning operations on a String."

  s.require_path = %w{lib}
  s.files = %w{ext/strscan/extconf.rb ext/strscan/strscan.c}
  s.extensions = %w{ext/strscan/extconf.rb}
  s.required_ruby_version = ">= 2.4.0"

  s.authors = ["Minero Aoki", "Sutou Kouhei"]
  s.email = [nil, "kou@cozmixng.org"]
  s.homepage = "https://github.com/ruby/strscan"
  s.licenses = ["Ruby", "BSD-2-Clause"]

  s.add_development_dependency "rake-compiler"
  s.add_development_dependency "benchmark-driver"
end
