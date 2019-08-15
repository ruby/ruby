# coding: utf-8
# frozen_string_literal: true
source_version = File.open(File.join(__dir__, "zlib.c")) {|f|
  f.gets("\n#define RUBY_ZLIB_VERSION ")
  f.gets[/\s*(".+")/, 1].undump
}
Gem::Specification.new do |spec|
  spec.name          = "zlib"
  spec.version       = source_version
  spec.authors       = ["Yukihiro Matsumoto", "UENO Katsuhiro"]
  spec.email         = ["matz@ruby-lang.org", nil]

  spec.summary       = %q{Ruby interface for the zlib compression/decompression library}
  spec.description   = %q{Ruby interface for the zlib compression/decompression library}
  spec.homepage      = "https://github.com/ruby/zlib"
  spec.license       = "BSD-2-Clause"

  spec.files         = [".gitignore", ".travis.yml", "Gemfile", "LICENSE.txt", "README.md", "Rakefile", "bin/console", "bin/setup", "ext/zlib/extconf.rb", "ext/zlib/zlib.c", "zlib.gemspec"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.extensions    = "ext/zlib/extconf.rb"
  spec.required_ruby_version = ">= 2.3.0"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rake-compiler"
end
