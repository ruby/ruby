# frozen_string_literal: true

name = File.basename(__FILE__, ".gemspec")
version = ["lib", Array.new(name.count("-")+1, "..").join("/")].find do |dir|
  break File.foreach(File.join(__dir__, dir, "#{name.tr('-', '/')}.rb")) do |line|
    /^\s*VERSION\s*=\s*"(.*)"/ =~ line and break $1
  end rescue nil
end

Gem::Specification.new do |spec|
  spec.name          = name
  spec.version       = version
  spec.authors       = ["Keiju ISHITSUKA"]
  spec.email         = ["keiju@ruby-lang.org"]

  spec.summary       = %q{Outputs a source level execution trace of a Ruby program.}
  spec.description   = %q{Outputs a source level execution trace of a Ruby program.}
  spec.homepage      = "https://github.com/ruby/tracer"
  spec.licenses      = ["Ruby", "BSD-2-Clause"]

  spec.files         = ["Gemfile", "LICENSE.txt", "README.md", "Rakefile", "lib/tracer.rb", "tracer.gemspec"]
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
