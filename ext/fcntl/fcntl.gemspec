# coding: utf-8
# frozen_string_literal: true

source_version = ["", "ext/fcntl/"].find do |dir|
  begin
    break File.open(File.join(__dir__, "#{dir}fcntl.c")) {|f|
      f.gets("\n#define FCNTL_VERSION ")
      f.gets[/\s*"(.+)"/, 1]
    }
  rescue Errno::ENOENT
  end
end

Gem::Specification.new do |spec|
  spec.name          = "fcntl"
  spec.version       = source_version
  spec.authors       = ["Yukihiro Matsumoto"]
  spec.email         = ["matz@ruby-lang.org"]

  spec.summary       = "Loads constants defined in the OS fcntl.h C header file"
  spec.description   = "Loads constants defined in the OS fcntl.h C header file"
  spec.homepage      = "https://github.com/ruby/fcntl"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.files         = ["ext/fcntl/extconf.rb", "ext/fcntl/fcntl.c"]
  spec.extra_rdoc_files = ["LICENSE.txt", "README.md"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
  spec.extensions    = "ext/fcntl/extconf.rb"
  spec.required_ruby_version = ">= 2.5.0"
end
