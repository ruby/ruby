# frozen_string_literal: true

version = ["", "ext/etc/"].find do |dir|
  begin
    break File.open(File.expand_path("../#{dir}/etc.c", __FILE__)) do |f|
      f.gets "\n#define RUBY_ETC_VERSION "
      f.gets[/"(.+)"/, 1]
    end
  rescue
    next
  end
end

Gem::Specification.new do |spec|
  spec.name          = "etc"
  spec.version       = version
  spec.authors       = ["Yukihiro Matsumoto"]
  spec.email         = ["matz@ruby-lang.org"]

  spec.summary       = %q{Provides access to information typically stored in UNIX /etc directory.}
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/ruby/etc"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  changelogs = Dir.glob("logs/ChangeLog-[1-9]*[^~]", base: __dir__)
  spec.files         = %w[
    BSDL
    COPYING
    README.md
    ChangeLog
    ext/etc/constdefs.h
    ext/etc/etc.c
    ext/etc/extconf.rb
    ext/etc/mkconstants.rb
    test/etc/test_etc.rb
  ] + changelogs
  spec.rdoc_options = ["--main", "README.md"]
  spec.extra_rdoc_files = spec.files.grep_v(/\.{rb,[ch]}\z/)
  spec.bindir        = "exe"
  spec.require_paths = ["lib"]
  spec.extensions    = %w{ext/etc/extconf.rb}

  spec.required_ruby_version = ">= 2.6.0"
end
